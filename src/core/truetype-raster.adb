package body Truetype.Raster
  with SPARK_Mode => On
is

   --  Fixed point: pixel space with 8 fractional bits, y growing DOWN (the
   --  bitmap's direction, the opposite of the font's).
   Frac : constant := 256;

   subtype Fix is Integer;

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

   type Edge is record
      X0, Y0, X1, Y1 : Fix := 0;   --  Y0 < Y1 after normalisation
      Dir            : Integer := 0;   --  +1 if the edge originally ran downward
   end record;

   Edges   : array (0 .. Max_Edges - 1) of Edge;
   N_Edges : Natural := 0;
   Peak    : Natural := 0;

   function Advance_Px
     (F : Font; G : Natural; Pixel_Size : Positive) return Natural
   is (Integer ((Long_Long_Integer (Truetype.Advance (F, G))
                 * Long_Long_Integer (Pixel_Size)
                 + Long_Long_Integer (F.Upem) / 2)
                / Long_Long_Integer (F.Upem)));

   function Peak_Edges return Natural is (Peak);
   function Edge_Capacity return Natural is (Max_Edges);

   --  One contour, expanded so that implicit on-curve midpoints are explicit.
   type XY is record
      X, Y : Fix := 0;
      On   : Boolean := False;
   end record;
   Exp   : array (0 .. Max_Contour_Pt - 1) of XY;
   N_Exp : Natural := 0;

   Cross_X   : array (0 .. Max_Crossings - 1) of Fix;
   Cross_D   : array (0 .. Max_Crossings - 1) of Integer;
   N_Cross   : Natural := 0;

   Acc : array (0 .. Max_Size - 1) of Natural;   --  per-pixel coverage accumulator

   -----------------
   -- Small maths --
   -----------------

   --  Integer square root (Newton); used only to pick a flattening step count.
   function Isqrt (N : Natural) return Natural is
      X, Y : Natural;
   begin
      if N < 2 then
         return N;
      end if;
      X := N;
      Y := (X + 1) / 2;
      while Y < X loop
         X := Y;
         Y := (X + N / X) / 2;
      end loop;
      return X;
   end Isqrt;

   --  Floor / ceiling division by Frac, correct for negatives (Ada's "/"
   --  truncates toward zero, which would fold the left/top edge inward).
   function Floor_Px (V : Fix) return Integer
   is (if V >= 0 then V / Frac else -((-V + Frac - 1) / Frac));

   function Ceil_Px (V : Fix) return Integer
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
      T, U : Integer;
   begin
      for I in 1 .. N loop
         --  B(t) at t = I/N, evaluated in 1/N units to stay in integers.
         T := I;
         U := N - I;
         QX := (U * U * X0 + 2 * U * T * CX + T * T * X1) / (N * N);
         QY := (U * U * Y0 + 2 * U * T * CY + T * T * Y1) / (N * N);
         Add_Edge (PX, PY, QX, QY, Ok);
         exit when not Ok;
         PX := QX;
         PY := QY;
      end loop;
   end Add_Quad;

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
      Cov         : out Coverage_Array;
      Ok          : out Boolean;
      Supersample : Positive := 4;
      Gain        : Positive := 16)
   is
      O    : Outline;
      --  F.Upem: a child package sees its parent's private part.
      Upem : constant Long_Long_Integer := Long_Long_Integer (F.Upem);

      --  Font units -> fixed-point pixel space.  Y is negated here, once: the
      --  font's y grows up, the bitmap's grows down.
      function SX (U : Integer) return Fix
      is (Integer ((Long_Long_Integer (U) * Long_Long_Integer (Pixel_Size)
                    * Frac) / Upem));
      function SY (U : Integer) return Fix is (-SX (U));

      X_Min, Y_Min, X_Max, Y_Max : Fix;
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
            declare
               Last : constant Natural := O.Ends (C);
               N    : constant Integer := Last - First + 1;
            begin
               if N >= 2 and then N <= Max_Contour_Pt / 2 then
                  --  Expand the contour, inserting the on-curve midpoint that
                  --  TrueType leaves implicit between two off-curve points.
                  N_Exp := 0;
                  for I in 0 .. N - 1 loop
                     declare
                        P : constant Point := O.Points (First + I);
                        Q : constant Point := O.Points (First + (I + 1) mod N);
                     begin
                        Exp (N_Exp) := (SX (P.X), SY (P.Y), P.On);
                        N_Exp := N_Exp + 1;
                        if not P.On and then not Q.On then
                           Exp (N_Exp) :=
                             ((SX (P.X) + SX (Q.X)) / 2,
                              (SY (P.Y) + SY (Q.Y)) / 2, True);
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
                     end loop;

                     if Found then
                        Cur_X := Exp (Start).X;
                        Cur_Y := Exp (Start).Y;
                        I := (Start + 1) mod N_Exp;
                        while Steps < N_Exp and then Ok loop
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
      W     := Ceil_Px (X_Max) - X_Off;
      H     := Ceil_Px (Y_Max) - Y_Off;

      if W <= 0 or else H <= 0 then
         W := 0; H := 0;
         Ok := True;
         return;
      end if;
      if W > Max_Size or else H > Max_Size or else Cov'Length < W * H then
         Ok := False;
         W := 0; H := 0;
         return;
      end if;

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
               Y : constant Fix :=
                 (Y_Off + PY) * Frac + ((2 * S + 1) * Frac) / (2 * SS);
            begin
               --  Crossings of the sample row with every edge.  The half-open
               --  test (Y0 <= Y < Y1) is what makes a shared vertex count once.
               N_Cross := 0;
               for I in 0 .. N_Edges - 1 loop
                  if Y >= Edges (I).Y0 and then Y < Edges (I).Y1
                    and then N_Cross < Max_Crossings
                  then
                     Cross_X (N_Cross) :=
                       Edges (I).X0
                       + Integer ((Long_Long_Integer (Y - Edges (I).Y0)
                                   * Long_Long_Integer (Edges (I).X1 - Edges (I).X0))
                                  / Long_Long_Integer (Edges (I).Y1 - Edges (I).Y0));
                     Cross_D (N_Cross) := Edges (I).Dir;
                     N_Cross := N_Cross + 1;
                  end if;
               end loop;

               --  Insertion sort by x (N_Cross is small -- a few dozen).
               for I in 1 .. N_Cross - 1 loop
                  declare
                     KX : constant Fix := Cross_X (I);
                     KD : constant Integer := Cross_D (I);
                     J  : Integer := I - 1;
                  begin
                     while J >= 0 and then Cross_X (J) > KX loop
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
                     Wind := Wind + Cross_D (I);
                     if Wind /= 0 then
                        declare
                           XA : constant Fix := Cross_X (I) - X_Off * Frac;
                           XB : constant Fix := Cross_X (I + 1) - X_Off * Frac;
                           P0 : constant Integer :=
                             Integer'Max (0, Floor_Px (XA));
                           P1 : constant Integer :=
                             Integer'Min (W - 1, Floor_Px (XB));
                        begin
                           for PX in P0 .. P1 loop
                              --  Overlap of [XA, XB) with pixel PX's column.
                              declare
                                 L : constant Fix :=
                                   Integer'Max (XA, PX * Frac);
                                 R : constant Fix :=
                                   Integer'Min (XB, (PX + 1) * Frac);
                              begin
                                 if R > L then
                                    Acc (PX) := Acc (PX) + (R - L);
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
         --  gain does not amplify rounding error).
         for PX in 0 .. W - 1 loop
            Cov (Cov'First + PY * W + PX) :=
              Unsigned_8
                (Integer'Min
                   (15, (Acc (PX) * 15 * Gain / 16 + Full / 2) / Full));
         end loop;
      end loop;

      Ok := True;
   end Render;

end Truetype.Raster;
