package body Truetype.Raster
  with SPARK_Mode => On
is

   --  Fixed point: pixel space with 8 fractional bits, y growing DOWN (the
   --  bitmap's direction, the opposite of the font's).
   Frac : constant := 256;

   --  A point's place in fixed pixel space.  Render refuses an outline point
   --  outside this range, so every coordinate below is bounded, and so is
   --  anything computed from a handful of them.
   Fix_Limit : constant := Max_Reach_Px * Frac;
   subtype Fix is Integer range -Fix_Limit .. Fix_Limit;

   --  A fixed-point value derived from a few coordinates and the pen, such
   --  as a crossing relative to the bitmap's left edge.
   subtype Wide is Integer range -2**24 .. 2**24;

   --  Working buffers are package-level (static) rather than local so a deep
   --  glyph cannot blow a small embedded stack.  Render is therefore NOT
   --  reentrant -- fine for the single-threaded firmware, and stated here
   --  because it is the one non-obvious property of this package.
   --  Sized from measurement in hangul_epd, whose raster_check reports the
   --  edge-list high-water mark, and rendering all 193 code points of this text
   --  at 26 px and 44 px peaks at 140 edges.  Flattening produces more segments
   --  at larger sizes (the step count grows with the square root of the
   --  deviation in pixels), so 1024 is roughly 3x headroom at Max_Size.  The
   --  first cut used 4096, which cost 80 KB of BSS for nothing.
   Max_Edges      : constant := 1024;
   Max_Contour_Pt : constant := 1024;
   Max_Crossings  : constant := 256;

   subtype Direction is Integer range -1 .. 1;

   type Edge is record
      X0, Y0, X1, Y1 : Fix := 0;   --  Y0 < Y1 after normalisation
      Dir            : Direction := 0;   --  +1 if the edge originally ran downward
   end record;

   Edges   : array (0 .. Max_Edges - 1) of Edge;
   N_Edges : Natural range 0 .. Max_Edges := 0;
   Peak    : Natural := 0;

   function Advance_Px
     (F : Font; G : Natural; Pixel_Size : Positive) return Natural
   is (Natural
         (Long_Long_Integer'Min
            (Long_Long_Integer (Natural'Last),
             (Long_Long_Integer (Truetype.Advance (F, G))
              * Long_Long_Integer (Pixel_Size)
              + Long_Long_Integer (F.Upem) / 2)
             / Long_Long_Integer (F.Upem))));

   function Peak_Edges return Natural is (Peak);
   function Edge_Capacity return Natural is (Max_Edges);

   --  One contour, expanded so that implicit on-curve midpoints are explicit.
   type XY is record
      X, Y : Fix := 0;
      On   : Boolean := False;
   end record;
   Exp   : array (0 .. Max_Contour_Pt - 1) of XY;
   N_Exp : Natural range 0 .. Max_Contour_Pt := 0;

   --  A crossing lies on an edge, so within an edge's own extent of its
   --  first end.
   subtype Cross_Fix is Integer range -3 * Fix_Limit .. 3 * Fix_Limit;

   Cross_X   : array (0 .. Max_Crossings - 1) of Cross_Fix;
   Cross_D   : array (0 .. Max_Crossings - 1) of Direction;
   N_Cross   : Natural range 0 .. Max_Crossings := 0;

   --  Per-pixel coverage accumulator.  The spans between consecutive sorted
   --  crossings are disjoint, so one sample row adds at most Frac to a pixel
   --  and a whole pixel row at most Supersample * Frac.  The bound is what
   --  keeps the final scaling in range; the accumulation saturates there,
   --  which by that argument it never reaches.
   subtype Acc_Value is Natural range 0 .. Max_Supersample * Frac;
   Acc : array (0 .. Max_Size - 1) of Acc_Value;

   -----------------
   -- Small maths --
   -----------------

   --  Integer square root (Newton); used only to pick a flattening step count.
   function Isqrt (N : Natural) return Natural
     with Pre  => N <= 2**24,
          Post => Isqrt'Result <= N
   is
      X, Y : Natural;
   begin
      if N < 2 then
         return N;
      end if;
      X := N;
      Y := (X + 1) / 2;
      while Y < X loop
         pragma Loop_Invariant (X in 1 .. N and then Y in 1 .. N);
         pragma Loop_Variant (Decreases => X);
         X := Y;
         Y := (X + N / X) / 2;
      end loop;
      return X;
   end Isqrt;

   --  Floor / ceiling division by Frac, correct for negatives (Ada's "/"
   --  truncates toward zero, which would fold the left/top edge inward).
   function Floor_Px (V : Wide) return Integer
   is (if V >= 0 then V / Frac else -((-V + Frac - 1) / Frac));

   function Ceil_Px (V : Wide) return Integer
   is (if V >= 0 then (V + Frac - 1) / Frac else -((-V) / Frac));

   -------------------
   -- Edge building --
   -------------------

   procedure Add_Edge (X0, Y0, X1, Y1 : Fix; Ok : in out Boolean) is
   begin
      --  Horizontal edges contribute no crossings; drop them.
      if Y0 = Y1 then
         return;
      end if;
      if N_Edges >= Max_Edges then
         Ok := False;
         return;
      end if;
      if Y0 < Y1 then
         Edges (N_Edges) := (X0, Y0, X1, Y1, +1);
      else
         Edges (N_Edges) := (X1, Y1, X0, Y0, -1);
      end if;
      N_Edges := N_Edges + 1;
      if N_Edges > Peak then
         Peak := N_Edges;
      end if;
   end Add_Edge;

   --  Flatten one quadratic Bezier into line segments.  The chord deviates from
   --  the curve by at most |P0 - 2*P1 + P2| / 4, and that error falls as 1/n^2
   --  with n segments, so n = ceil (sqrt (2.5 * d)) holds it under ~0.1 px.
   procedure Add_Quad (X0, Y0, CX, CY, X1, Y1 : Fix; Ok : in out Boolean) is
      DX : constant Integer := abs (X0 - 2 * CX + X1);
      DY : constant Integer := abs (Y0 - 2 * CY + Y1);
      D  : constant Natural := (DX + DY) / Frac;          --  deviation in pixels
      N  : constant Positive :=
        Integer'Min (32, Integer'Max (1, Isqrt (5 * D / 2) + 1));
      PX : Fix := X0;
      PY : Fix := Y0;
      QX, QY : Fix;
      T, U : Natural;

      --  B(t) at t = T/N, evaluated in 1/N units to stay in integers.  The
      --  weights U*U, 2*U*T and T*T sum to N*N, so the result is a convex
      --  combination of three Fix values and the clamp never bites; it only
      --  states that bound where the prover can see it.  Computed in 64
      --  bits, since each weighted term alone may not fit in 32.
      function Bez (A, C, B : Fix) return Fix is
        (Fix (Long_Long_Integer'Max
                (-Fix_Limit,
                 Long_Long_Integer'Min
                   (Fix_Limit,
                    (Long_Long_Integer (U) * Long_Long_Integer (U)
                       * Long_Long_Integer (A)
                     + 2 * Long_Long_Integer (U) * Long_Long_Integer (T)
                       * Long_Long_Integer (C)
                     + Long_Long_Integer (T) * Long_Long_Integer (T)
                       * Long_Long_Integer (B))
                    / Long_Long_Integer (N * N)))))
      with Pre => U <= 32 and then T <= 32;
   begin
      for I in 1 .. N loop
         T := I;
         U := N - I;
         QX := Bez (X0, CX, X1);
         QY := Bez (Y0, CY, Y1);
         Add_Edge (PX, PY, QX, QY, Ok);
         exit when not Ok;
         PX := QX;
         PY := QY;
      end loop;
   end Add_Quad;

   --  Row R of a W-wide bitmap of H rows ends within its W * H bytes.  Stated
   --  apart so the prover sees the multiplication without Render's context.
   procedure Lemma_Row_Inside (R, W, H : Natural)
     with Ghost,
          Pre  => R < H and then W <= Max_Size and then H <= Max_Size,
          Post => R * W + W <= H * W
   is
   begin
      pragma Assert (H * W - (R + 1) * W = (H - (R + 1)) * W);
   end Lemma_Row_Inside;

   ------------
   -- Render --
   ------------

   procedure Render
     (F           : Font;
      G           : Natural;
      Pixel_Size  : Positive;
      W, H        : out Natural;
      X_Off       : out Integer;
      Y_Off       : out Integer;
      Adv         : out Natural;
      Cov         : in out Coverage_Array;
      Ok          : out Boolean;
      Supersample : Positive := 4;
      Gain        : Positive := 16)
   is
      O    : Outline;
      --  F.Upem: a child package sees its parent's private part.
      Upem : constant Long_Long_Integer := Long_Long_Integer (F.Upem);

      --  Font units -> fixed-point pixel space, before the range check that
      --  admits the result as a Fix.  A coordinate is 19 bits and the size 31,
      --  so the product fits comfortably in 64.
      function SX (U : Coord) return Long_Long_Integer
      is ((Long_Long_Integer (U) * Long_Long_Integer (Pixel_Size) * Frac)
          / Upem);

      X_Min, Y_Min, X_Max, Y_Max : Fix;
      WI, HI : Integer;
      SS  : constant Positive := Supersample;
      Full : constant Positive := SS * Frac;   --  accumulator value for full coverage
   begin
      W := 0; H := 0; X_Off := 0; Y_Off := 0;
      Adv := Advance_Px (F, G, Pixel_Size);

      Get_Outline (F, G, O, Ok);
      if not Ok or else O.N_Contours = 0 then
         return;                       --  blank glyph (a space) still has Adv
      end if;

      ---------------------------------------------------------------------
      --  1. Flatten every contour into the edge list.
      ---------------------------------------------------------------------
      N_Edges := 0;
      declare
         First : Natural := 0;
      begin
         for C in 0 .. O.N_Contours - 1 loop
            pragma Loop_Invariant
              (Ok and then First = (if C = 0 then 0 else O.Ends (C - 1) + 1));
            declare
               Last : constant Natural := O.Ends (C);
               N    : constant Integer := Last - First + 1;
            begin
               if N >= 2 and then N <= Max_Contour_Pt / 2 then
                  --  Expand the contour, inserting the on-curve midpoint that
                  --  TrueType leaves implicit between two off-curve points.
                  --  Y is negated here, once: the font's y grows up, the
                  --  bitmap's grows down.
                  N_Exp := 0;
                  for I in 0 .. N - 1 loop
                     pragma Loop_Invariant (Ok and then N_Exp in I .. 2 * I);
                     declare
                        P  : constant Point := O.Points (First + I);
                        Q  : constant Point := O.Points (First + (I + 1) mod N);
                        PX : constant Long_Long_Integer := SX (P.X);
                        PY : constant Long_Long_Integer := -SX (P.Y);
                        QX : constant Long_Long_Integer := SX (Q.X);
                        QY : constant Long_Long_Integer := -SX (Q.Y);
                     begin
                        if abs PX > Fix_Limit or else abs PY > Fix_Limit
                          or else abs QX > Fix_Limit or else abs QY > Fix_Limit
                        then
                           Ok := False;
                           exit;
                        end if;
                        Exp (N_Exp) := (Fix (PX), Fix (PY), P.On);
                        N_Exp := N_Exp + 1;
                        if not P.On and then not Q.On then
                           Exp (N_Exp) :=
                             ((Fix (PX) + Fix (QX)) / 2,
                              (Fix (PY) + Fix (QY)) / 2, True);
                           N_Exp := N_Exp + 1;
                        end if;
                     end;
                  end loop;

                  --  Walk the expanded contour.  It now alternates on-curve and
                  --  off-curve, so each step is either a line to the next
                  --  on-curve point or a quadratic through one control point.
                  declare
                     Start : Natural := 0;
                     Found : Boolean := False;
                     Cur_X, Cur_Y : Fix;
                     I     : Natural;
                     Steps : Natural := 0;
                  begin
                     for K in 0 .. N_Exp - 1 loop
                        if Exp (K).On then
                           Start := K;
                           Found := True;
                           exit;
                        end if;
                        pragma Loop_Invariant (not Found);
                     end loop;

                     if Ok and then Found then
                        Cur_X := Exp (Start).X;
                        Cur_Y := Exp (Start).Y;
                        I := (Start + 1) mod N_Exp;
                        while Steps < N_Exp and then Ok loop
                           pragma Loop_Invariant (I < N_Exp);
                           if Exp (I).On then
                              Add_Edge (Cur_X, Cur_Y, Exp (I).X, Exp (I).Y, Ok);
                              Cur_X := Exp (I).X;
                              Cur_Y := Exp (I).Y;
                              I := (I + 1) mod N_Exp;
                              Steps := Steps + 1;
                           else
                              declare
                                 J : constant Natural := (I + 1) mod N_Exp;
                              begin
                                 Add_Quad (Cur_X, Cur_Y, Exp (I).X, Exp (I).Y,
                                           Exp (J).X, Exp (J).Y, Ok);
                                 Cur_X := Exp (J).X;
                                 Cur_Y := Exp (J).Y;
                                 I := (J + 1) mod N_Exp;
                                 Steps := Steps + 2;
                              end;
                           end if;
                        end loop;
                        --  Close the contour.
                        Add_Edge (Cur_X, Cur_Y, Exp (Start).X, Exp (Start).Y, Ok);
                     end if;
                  end;
               end if;
               First := Last + 1;
            end;
            exit when not Ok;
         end loop;
      end;

      if not Ok then
         return;
      end if;
      if N_Edges = 0 then
         Ok := True;
         return;                       --  degenerate outline: nothing to fill
      end if;

      ---------------------------------------------------------------------
      --  2. Bounding box from the FLATTENED edges (not the control points,
      --     whose convex hull would over-estimate it and add blank margins).
      ---------------------------------------------------------------------
      X_Min := Edges (0).X0; X_Max := X_Min;
      Y_Min := Edges (0).Y0; Y_Max := Y_Min;
      for I in 0 .. N_Edges - 1 loop
         X_Min := Integer'Min (X_Min, Integer'Min (Edges (I).X0, Edges (I).X1));
         X_Max := Integer'Max (X_Max, Integer'Max (Edges (I).X0, Edges (I).X1));
         Y_Min := Integer'Min (Y_Min, Edges (I).Y0);
         Y_Max := Integer'Max (Y_Max, Edges (I).Y1);
      end loop;

      X_Off := Floor_Px (X_Min);
      Y_Off := Floor_Px (Y_Min);
      WI    := Ceil_Px (X_Max) - X_Off;
      HI    := Ceil_Px (Y_Max) - Y_Off;

      if WI <= 0 or else HI <= 0 then
         Ok := True;
         return;
      end if;
      --  Cov's bounds are compared rather than its 'Length, which for a
      --  buffer spanning all of Natural would not fit in Integer.
      if WI > Max_Size or else HI > Max_Size
        or else Cov'Last < Cov'First
        or else Cov'Last - Cov'First < WI * HI - 1
      then
         Ok := False;
         return;
      end if;
      W := WI;
      H := HI;

      ---------------------------------------------------------------------
      --  3. Scan.  Vertically: SS sample rows per pixel row, nonzero winding.
      --     Horizontally: the exact overlap of each filled span with each
      --     pixel, so a near-vertical stem gets a true partial grey rather
      --     than a second round of sampling.
      ---------------------------------------------------------------------
      for PY in 0 .. H - 1 loop
         Acc (0 .. W - 1) := (others => 0);

         for S in 0 .. SS - 1 loop
            declare
               --  Centre of this sample row, in fixed pixel space.
               Y : constant Integer :=
                 (Y_Off + PY) * Frac + ((2 * S + 1) * Frac) / (2 * SS);
            begin
               --  Crossings of the sample row with every edge.  The half-open
               --  test (Y0 <= Y < Y1) is what makes a shared vertex count once.
               N_Cross := 0;
               for I in 0 .. N_Edges - 1 loop
                  if Y >= Edges (I).Y0 and then Y < Edges (I).Y1
                    and then N_Cross < Max_Crossings
                  then
                     --  0 <= Y - Y0 < Y1 - Y0, so the offset along the edge is
                     --  within X1 - X0 and the clamp never bites; it only
                     --  states that bound where the prover can see it.
                     Cross_X (N_Cross) :=
                       Edges (I).X0
                       + Integer
                           (Long_Long_Integer'Max
                              (-2 * Fix_Limit,
                               Long_Long_Integer'Min
                                 (2 * Fix_Limit,
                                  (Long_Long_Integer (Y - Edges (I).Y0)
                                   * Long_Long_Integer (Edges (I).X1 - Edges (I).X0))
                                  / Long_Long_Integer (Edges (I).Y1 - Edges (I).Y0))));
                     Cross_D (N_Cross) := Edges (I).Dir;
                     N_Cross := N_Cross + 1;
                  end if;
               end loop;

               --  Insertion sort by x (N_Cross is small -- a few dozen).
               for I in 1 .. N_Cross - 1 loop
                  declare
                     KX : constant Cross_Fix := Cross_X (I);
                     KD : constant Direction := Cross_D (I);
                     J  : Integer := I - 1;
                  begin
                     while J >= 0 and then Cross_X (J) > KX loop
                        pragma Loop_Invariant (J < I);
                        pragma Loop_Variant (Decreases => J);
                        Cross_X (J + 1) := Cross_X (J);
                        Cross_D (J + 1) := Cross_D (J);
                        J := J - 1;
                     end loop;
                     Cross_X (J + 1) := KX;
                     Cross_D (J + 1) := KD;
                  end;
               end loop;

               --  Nonzero winding: a span is filled wherever the running sum of
               --  edge directions is non-zero.
               declare
                  Wind : Integer := 0;
               begin
                  for I in 0 .. N_Cross - 2 loop
                     pragma Loop_Invariant (Wind in -I .. I);
                     Wind := Wind + Cross_D (I);
                     if Wind /= 0 then
                        declare
                           XA : constant Wide := Cross_X (I) - X_Off * Frac;
                           XB : constant Wide := Cross_X (I + 1) - X_Off * Frac;
                           P0 : constant Integer :=
                             Integer'Max (0, Floor_Px (XA));
                           P1 : constant Integer :=
                             Integer'Min (W - 1, Floor_Px (XB));
                        begin
                           for PX in P0 .. P1 loop
                              --  Overlap of [XA, XB) with pixel PX's column.
                              declare
                                 L : constant Integer :=
                                   Integer'Max (XA, PX * Frac);
                                 R : constant Integer :=
                                   Integer'Min (XB, (PX + 1) * Frac);
                              begin
                                 if R > L then
                                    Acc (PX) :=
                                      Integer'Min
                                        (Acc_Value'Last, Acc (PX) + (R - L));
                                 end if;
                              end;
                           end loop;
                        end;
                     end if;
                  end loop;
               end;
            end;
         end loop;

         --  Accumulator -> the 16 levels the panel and the atlases both use,
         --  with the stem-darkening gain folded in before quantising (so the
         --  gain does not amplify rounding error).  In 64 bits, since Gain is
         --  not bounded.
         Lemma_Row_Inside (PY, W, H);
         for PX in 0 .. W - 1 loop
            Cov (Cov'First + PY * W + PX) :=
              Unsigned_8
                (Long_Long_Integer'Min
                   (15,
                    (Long_Long_Integer (Acc (PX)) * 15
                     * Long_Long_Integer (Gain) / 16
                     + Long_Long_Integer (Full) / 2)
                    / Long_Long_Integer (Full)));
         end loop;
      end loop;

      Ok := True;
   end Render;

end Truetype.Raster;
