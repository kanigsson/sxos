with Text_Raster;
with UTF8;

package body Page_Layout
  with SPARK_Mode => On
is
   use type Hyphenation.Trie_Ref;
   use type UTF8.Code_Point;

   LF : constant Character := ASCII.LF;

   function Make
     (T : Text_Metrics.Table; F : Truetype.Font;
      Col_Width, Area_Height : Positive) return Geometry
   is
      Size : constant Positive := Text_Metrics.Size (T);
      --  The face's metrics come from a file on the card: clamp them to
      --  Max_Px, where a real face never reaches.
      Asc  : constant Px :=
        Natural'Min (Max_Px, Text_Raster.Ascent_Px (F, Size));
      Desc : constant Px :=
        Natural'Min (Max_Px, Text_Raster.Descent_Px (F, Size));
      --  About 1.35 em from baseline to baseline, or the face's own line
      --  spacing when that is looser.
      LH   : constant Positive_Px :=
        Natural'Min
          (Max_Px,
           Positive'Max (Text_Raster.Line_Height_Px (F, Size),
                         (Size * 135 + 50) / 100));
   begin
      return (Size        => Size,
              Col_Width   => Col_Width,
              Area_Height => Area_Height,
              Line_Height => LH,
              --  The line's spare height is split above and below; a face
              --  whose descent alone exceeds the line puts the baseline at
              --  the top.
              Ascent      => Natural'Max (0, Asc + (LH - Asc - Desc) / 2),
              Indent      => Size * 3 / 2,
              Para_Gap    => LH / 4,
              Hyph        => null);
   end Make;

   --  A code point after which a line may break inside a word: hyphen,
   --  hyphen (U+2010), en and em dash, zero-width space.
   function Breaks_After (C : UTF8.Code_Point) return Boolean is
     (C = Character'Pos ('-') or else C = 16#2010# or else C = 16#2013#
      or else C = 16#2014# or else C = 16#200B#);

   Soft_Hyphen : constant UTF8.Code_Point := 16#AD#;

   --  Where to break inside the word Text (Run_First .. Run_Last), a run of
   --  letters starting Run_W pixels into the line after the character
   --  Before: after the last hyphenation point whose part of the word, with
   --  a hyphen, fits in Budget.  Last is that part's last byte, Width the
   --  line's width up to and with the hyphen.  Found is False when no point
   --  fits.
   procedure Hyphenate_Run
     (T         : Text_Metrics.Table;
      F         : Truetype.Font;
      H         : Hyphenation.Trie;
      Text      : String;
      Run_First : Positive;
      Run_Last  : Positive;
      Run_W     : Natural;
      Before    : UTF8.Code_Point;
      Hyphen_W  : Natural;
      Budget    : Natural;
      Last      : out Natural;
      Width     : out Natural;
      Found     : out Boolean)
     with Pre  => Text'First = 1 and then Text'Last < Positive'Last
                  and then Run_First <= Run_Last
                  and then Run_Last <= Text'Last,
          Post => (if Found then Last in Run_First .. Run_Last),
          Always_Terminates
   is
      Max : constant := Hyphenation.Max_Word;
      Word   : Hyphenation.Code_Array (1 .. Max) := (others => 0);
      Breaks : Hyphenation.Break_Array (1 .. Max) := (others => False);
      --  Ends (I): the last byte of letter I; Widths (I): letters 1 .. I.
      Ends   : array (1 .. Max) of Natural := (others => 0);
      Widths : array (0 .. Max) of Natural := (others => 0);
      N      : Natural := 0;
      P      : Positive := Run_First;
      C      : UTF8.Code_Point;
   begin
      Last := 0;
      Width := 0;
      Found := False;
      while P <= Run_Last loop
         pragma Loop_Invariant (N <= Max);
         pragma Loop_Invariant (P in Run_First .. Run_Last);
         pragma Loop_Invariant
           (for all K in 1 .. N => Ends (K) in Run_First .. P - 1);
         pragma Loop_Invariant (not Found);
         pragma Loop_Variant (Increases => P);
         if N = Max then
            return;   --  too long to hyphenate
         end if;
         UTF8.Next_Code (Text, P, C);
         N := N + 1;
         Word (N) := C;
         Ends (N) := P - 1;
         --  The first letter's kerning with Before goes into Start below.
         Widths (N) :=
           Add_Sat (Add_Kern (Widths (N - 1),
                              (if N = 1 then 0
                               else Text_Metrics.Kern (T, Word (N - 1), C))),
                    Text_Metrics.Advance (T, F, C));
      end loop;
      if N = 0 then
         return;
      end if;
      Hyphenation.Hyphenate (H, Word (1 .. N), Breaks (1 .. N));
      declare
         Start : constant Natural :=
           Add_Kern (Run_W, Text_Metrics.Kern (T, Before, Word (1)));
         W     : Natural;
      begin
         for I in reverse 1 .. N - 1 loop
            if Breaks (I) then
               W := Add_Sat
                 (Add_Kern (Add_Sat (Start, Widths (I)),
                            Text_Metrics.Kern
                              (T, Word (I), Character'Pos ('-'))),
                  Hyphen_W);
               if W <= Budget then
                  Last := Ends (I);
                  Width := W;
                  Found := True;
                  return;
               end if;
            end if;
         end loop;
      end;
   end Hyphenate_Run;

   procedure Break_Line
     (T    : Text_Metrics.Table;
      F    : Truetype.Font;
      G    : Geometry;
      Text : String;
      From : Positive;
      L    : out Line)
   is
      Indented : constant Boolean := From = 1 or else Text (From - 1) = LF;
      Budget   : constant Natural :=
        (if Indented then Natural'Max (0, G.Col_Width - G.Indent)
         else G.Col_Width);
      Space_W  : constant Natural :=
        Text_Metrics.Advance (T, F, Character'Pos (' '));
      Hyphen_W : constant Natural :=
        Text_Metrics.Advance (T, F, Character'Pos ('-'));

      Q      : Positive := From;
      Q2     : Positive;
      C      : UTF8.Code_Point;
      A      : Natural;
      K      : Integer;
      W      : Natural := 0;
      Spaces : Natural := 0;
      --  The visible character before Q, to kern with (none after a space).
      Prev   : UTF8.Code_Point := Text_Metrics.No_Code;

      --  The latest place the line could end: its last byte, where the
      --  next line would start, its width and its spaces, and whether a
      --  hyphen is drawn there.
      Have_Break : Boolean := False;
      B_Last     : Natural := 0;
      B_Next     : Positive := From;
      B_Width    : Natural := 0;
      B_Spaces   : Natural := 0;
      B_Hyphen   : Boolean := False;

      --  The run of letters the line is in (or last was in): where it
      --  starts, the width and spaces before it, and whether it has a soft
      --  hyphen (then only those break it).
      In_Run     : Boolean := False;
      Run_First  : Positive := From;
      Run_W      : Natural := 0;
      Run_Before : UTF8.Code_Point := Text_Metrics.No_Code;
      Run_Spaces : Natural := 0;
      Run_Shy    : Boolean := False;
   begin
      L := (First    => From,
            Last     => From - 1,
            Next     => From + 1,
            Width    => 0,
            Spaces   => 0,
            Indented => Indented,
            Para_End => True,
            Hyphen   => False);

      loop
         pragma Loop_Invariant (Q in From .. Text'Last + 1);
         pragma Loop_Invariant (Spaces <= Q - From);
         pragma Loop_Invariant (Run_First in From .. Text'Last);
         pragma Loop_Invariant (B_Next in From .. Text'Last + 1);
         pragma Loop_Invariant (if Have_Break then B_Next > From);
         pragma Loop_Invariant (B_Last <= Text'Last);
         pragma Loop_Variant (Increases => Q);
         if Q > Text'Last or else Text (Q) = LF then
            --  The paragraph ends on this line.
            L.Last := Q - 1;
            L.Next := (if Q > Text'Last then Q else Q + 1);
            L.Width := W;
            L.Spaces := Spaces;
            return;
         end if;

         if Text (Q) = ' ' then
            --  Text is white-space collapsed, but tolerate runs of spaces.
            if Q > From and then Text (Q - 1) /= ' ' then
               Have_Break := True;
               B_Last := Q - 1;
               B_Width := W;
               B_Spaces := Spaces;
               B_Hyphen := False;
            end if;
            Q2 := Q + 1;
            B_Next := Q2;
            Spaces := Spaces + 1;
            W := Add_Sat (W, Space_W);
            Prev := Text_Metrics.No_Code;
            In_Run := False;
         else
            Q2 := Q;
            UTF8.Next_Code (Text, Q2, C);
            if C = Soft_Hyphen then
               --  Invisible, but a break with a hyphen drawn.
               Run_Shy := True;
               if Q > From and then Text (Q - 1) /= ' '
                 and then Q2 <= Text'Last and then Text (Q2) /= ' '
                 and then Text (Q2) /= LF
                 and then Add_Sat
                   (Add_Kern (W, Text_Metrics.Kern
                                   (T, Prev, Character'Pos ('-'))),
                    Hyphen_W) <= Budget
               then
                  Have_Break := True;
                  B_Last := Q - 1;
                  B_Next := Q2;
                  B_Width := Add_Sat
                    (Add_Kern (W, Text_Metrics.Kern
                                    (T, Prev, Character'Pos ('-'))),
                     Hyphen_W);
                  B_Spaces := Spaces;
                  B_Hyphen := True;
               end if;
            else
               if Breaks_Between (Prev, C) and then Q > From then
                  Have_Break := True;
                  B_Last := Q - 1;
                  B_Next := Q;
                  B_Width := W;
                  B_Spaces := Spaces;
                  B_Hyphen := False;
               end if;
               A := Text_Metrics.Advance (T, F, C);
               K := Text_Metrics.Kern (T, Prev, C);
               if Add_Sat (Add_Kern (W, K), A) > Budget and then Q > From
               then
                  exit;
               end if;
               if not Hyphenation.Is_Letter (C) then
                  In_Run := False;
               elsif not In_Run then
                  In_Run := True;
                  Run_First := Q;
                  Run_W := W;
                  Run_Before := Prev;
                  Run_Spaces := Spaces;
                  Run_Shy := False;
               end if;
               W := Add_Sat (Add_Kern (W, K), A);
               Prev := C;
               if Breaks_After (C) and then Q > From
                 and then Text (Q - 1) /= ' '
                 and then Q2 <= Text'Last and then Text (Q2) /= ' '
                 and then Text (Q2) /= LF
               then
                  Have_Break := True;
                  B_Last := Q2 - 1;
                  B_Next := Q2;
                  B_Width := W;
                  B_Spaces := Spaces;
                  B_Hyphen := False;
               end if;
            end if;
         end if;
         Q := Q2;
      end loop;

      --  The code point C at Q overflows the column.
      L.Para_End := False;

      --  Hyphenate the word it is in, or the one it ends.  Any break found
      --  there is later than the ones before the word.
      if G.Hyph /= null and then In_Run then
         declare
            Run_Last : Natural := Q - 1;
            Shy      : Boolean := Run_Shy;
            P        : Positive := Q;
            P2       : Positive;
            C2       : UTF8.Code_Point;
            H_Last   : Natural;
            H_Width  : Natural;
            Found    : Boolean;
         begin
            if Hyphenation.Is_Letter (C) then
               while P <= Text'Last loop
                  pragma Loop_Invariant (P in Q .. Text'Last);
                  pragma Loop_Invariant (Run_Last in Q - 1 .. P - 1);
                  pragma Loop_Variant (Increases => P);
                  P2 := P;
                  UTF8.Next_Code (Text, P2, C2);
                  if C2 = Soft_Hyphen then
                     Shy := True;
                  elsif not Hyphenation.Is_Letter (C2) then
                     exit;
                  end if;
                  Run_Last := P2 - 1;
                  P := P2;
               end loop;
            end if;
            if not Shy and then Run_Last >= Run_First then
               Hyphenate_Run
                 (T, F, G.Hyph.all, Text, Run_First, Run_Last, Run_W,
                  Run_Before, Hyphen_W, Budget, H_Last, H_Width, Found);
               if Found then
                  L.Last := H_Last;
                  L.Next := H_Last + 1;
                  L.Width := H_Width;
                  L.Spaces := Run_Spaces;
                  L.Hyphen := True;
                  return;
               end if;
            end if;
         end;
      end if;

      if Have_Break then
         L.Last := B_Last;
         L.Next := B_Next;
         L.Width := B_Width;
         L.Spaces := B_Spaces;
         L.Hyphen := B_Hyphen;
      else
         L.Last := Q - 1;
         L.Next := Q;
         L.Width := W;
         L.Spaces := Spaces;
      end if;

      --  A break at a space starts the next line after the space(s).
      while L.Next <= Text'Last and then Text (L.Next) = ' ' loop
         pragma Loop_Invariant (L.Next > From and then L.Last <= Text'Last);
         pragma Loop_Invariant (L.First = From);
         pragma Loop_Variant (Increases => L.Next);
         L.Next := L.Next + 1;
      end loop;
   end Break_Line;

   --  Setting a paragraph as a whole.

   --  The costs, after TeX's (\linepenalty, \hyphenpenalty, ...), scaled
   --  down where a column of ~40 characters needs more leeway.
   Line_Penalty   : constant := 10;
   Hyphen_Penalty : constant := 50;
   Double_Hyphen  : constant := 3_000;   --  two flagged lines in a row
   Final_Hyphen   : constant := 5_000;   --  the second-last line flagged
   Adjacent       : constant := 3_000;   --  fitness two classes apart
   --  Badness grows as 100 r**3 up to here, and by a pixel of excess a
   --  point beyond: unlike TeX's, it is not capped, so that of two lines
   --  too loose to justify, the shorter still costs more.
   Max_Badness    : constant := 10_000_000;
   --  A first try without hyphenation points takes lines up to this.
   Pretolerance   : constant := 100;

   function Diff (A, B : Natural) return Natural is
     (if A >= B then A - B else 0);

   function Add_Cost (A, B : Demerits) return Demerits is
     (if B <= Infinite - A then A + B else Infinite);

   --  100 (Excess / Capacity)**3, or Max_Badness + Excess beyond
   --  Max_Badness (and for a line with no space to stretch).
   function Badness (Excess : Px; Capacity : Long_Long_Integer)
     return Natural
     with Pre  => Capacity >= 0,
          Post => Badness'Result <= Max_Badness + Max_Px
   is
      E : constant Long_Long_Integer := Long_Long_Integer (Excess);
      B : Long_Long_Integer;
   begin
      if E = 0 then
         return 0;
      elsif Capacity > 5 * E then
         return 0;
      elsif Capacity = 0 or else E > 100 * Capacity then
         return Max_Badness + Excess;
      end if;
      pragma Assert (Capacity <= 5 * Max_Px);
      B := 100 * E * E * E / (Capacity * Capacity * Capacity);
      return (if B > Max_Badness then Max_Badness + Excess else Natural (B));
   end Badness;

   --  The hyphenation points of the run of letters starting at Q, before
   --  PE: Points (I) for a break after letter I of the N letters.  N is 0
   --  when the run is not to be hyphenated: it has a soft hyphen (then only
   --  those break it), or it is longer than Hyphenation.Max_Word.
   procedure Word_Points
     (H      : Hyphenation.Trie;
      Text   : String;
      Q, PE  : Positive;
      Points : out Hyphenation.Break_Array;
      N      : out Natural)
     with Pre  => Text'First = 1 and then Text'Last < Positive'Last
                  and then Q < PE and then PE <= Text'Last + 1
                  and then Points'First = 1
                  and then Points'Last = Hyphenation.Max_Word,
          Post => N <= Hyphenation.Max_Word,
          Always_Terminates
   is
      Max  : constant := Hyphenation.Max_Word;
      Word : Hyphenation.Code_Array (1 .. Max) := (others => 0);
      P    : Positive := Q;
      P2   : Positive;
      C    : UTF8.Code_Point;
   begin
      Points := (others => False);
      N := 0;
      while P < PE loop
         pragma Loop_Invariant (P in Q .. PE - 1 and then N <= Max);
         pragma Loop_Variant (Increases => P);
         P2 := P;
         UTF8.Next_Code (Text, P2, C);
         if C = Soft_Hyphen or else (N = Max and then Hyphenation.Is_Letter (C))
         then
            N := 0;
            return;
         end if;
         exit when not Hyphenation.Is_Letter (C);
         N := N + 1;
         Word (N) := C;
         P := P2;
      end loop;
      if N > 0 then
         Hyphenation.Hyphenate (H, Word (1 .. N), Points (1 .. N));
      end if;
   end Word_Points;

   --  List where the paragraph Text (PS .. PE - 1) may break, in W.Brk
   --  (1 .. N); W.Brk (N) is its end, W.Brk (0) its start.  With Liang, the
   --  hyphenation points of G.Hyph's patterns too.  Ok is False when there
   --  are more than Max_Breaks.
   procedure Scan_Paragraph
     (T      : Text_Metrics.Table;
      F      : Truetype.Font;
      G      : Geometry;
      Text   : String;
      PS, PE : Positive;
      Liang  : Boolean;
      W      : in out Workspace;
      N      : out Natural;
      Ok     : out Boolean)
     with Pre  => Text'First = 1 and then Text'Last < Positive'Last
                  and then PS <= PE and then PE <= Text'Last + 1,
          Post => N <= Max_Breaks and then (if Ok then N >= 1),
          Always_Terminates
   is
      Space_W  : constant Natural :=
        Text_Metrics.Advance (T, F, Character'Pos (' '));
      Hyphen_W : constant Natural :=
        Text_Metrics.Advance (T, F, Character'Pos ('-'));
      Hyph     : constant Boolean := Liang and then G.Hyph /= null;

      Q      : Positive := PS;
      Q2     : Positive;
      R      : Positive;
      C      : UTF8.Code_Point;
      K      : Integer;
      X      : Natural := 0;   --  the paragraph's width so far
      Sp     : Natural := 0;   --  and its spaces
      Prev   : UTF8.Code_Point := Text_Metrics.No_Code;
      --  Breaks Pend .. N start their line at the next visible character.
      Pend   : Natural := 0;

      --  The letter run the scan is in, its hyphenation points, and the
      --  letters of it passed.
      In_Run : Boolean := False;
      Points : Hyphenation.Break_Array (1 .. Hyphenation.Max_Word) :=
        (others => False);
      Run_N  : Natural := 0;
      Run_I  : Natural := 0;

      --  Add a break, not yet followed by the line after it.
      procedure Push
        (Last : Natural; Next : Positive; End_W, Penalty : Natural;
         Hyphen, Flagged : Boolean)
        with Pre  => N <= Max_Breaks,
             Post => N in N'Old .. Max_Breaks
      is
      begin
         if N = Max_Breaks then
            Ok := False;
            return;
         end if;
         N := N + 1;
         W.Brk (N).Last := Last;
         W.Brk (N).Next := Next;
         W.Brk (N).End_W := End_W;
         W.Brk (N).End_Sp := Sp;
         W.Brk (N).Start_W := End_W;
         W.Brk (N).Start_Sp := Sp;
         W.Brk (N).Penalty := Penalty;
         W.Brk (N).Hyphen := Hyphen;
         W.Brk (N).Flagged := Flagged;
         W.Brk (N).Succ := 0;
      end Push;

      --  Push, the line after it to start at the next visible character.
      procedure Add
        (Last : Natural; Next : Positive; End_W, Penalty : Natural;
         Hyphen, Flagged : Boolean)
        with Pre  => N <= Max_Breaks and then Pend <= N,
             Post => N <= Max_Breaks and then Pend <= N
      is
      begin
         Push (Last, Next, End_W, Penalty, Hyphen, Flagged);
         if Pend = 0 and then N > 0 then
            Pend := N;
         end if;
      end Add;
   begin
      N := 0;
      Ok := True;
      W.Brk (0).Last := PS - 1;
      W.Brk (0).Next := PS;
      W.Brk (0).End_W := 0;
      W.Brk (0).Start_W := 0;
      W.Brk (0).End_Sp := 0;
      W.Brk (0).Start_Sp := 0;
      W.Brk (0).Penalty := 0;
      W.Brk (0).Hyphen := False;
      W.Brk (0).Flagged := False;
      W.Brk (0).Cost := (Decent => 0, others => Infinite);
      W.Brk (0).Succ := 0;

      while Q < PE loop
         pragma Loop_Invariant (Q in PS .. PE - 1);
         pragma Loop_Invariant (N <= Max_Breaks and then Pend <= N);
         pragma Loop_Invariant (Run_N <= Hyphenation.Max_Word);
         pragma Loop_Variant (Increases => Q);
         exit when not Ok;
         if Text (Q) = ' ' then
            if Q > PS and then Text (Q - 1) /= ' ' then
               --  A break, unless only spaces follow in the paragraph.
               R := Q;
               while R < PE and then Text (R) = ' ' loop
                  pragma Loop_Invariant (R in Q .. PE - 1);
                  pragma Loop_Variant (Increases => R);
                  R := R + 1;
               end loop;
               if R < PE then
                  Add (Q - 1, R, X, 0, False, False);
               end if;
            end if;
            X := Add_Sat (X, Space_W);
            Sp := Add_Sat (Sp, 1);
            Prev := Text_Metrics.No_Code;
            In_Run := False;
            Run_N := 0;
            Q2 := Q + 1;
         else
            Q2 := Q;
            UTF8.Next_Code (Text, Q2, C);
            if C = Soft_Hyphen then
               --  Invisible, but a break with a hyphen drawn.
               if Q > PS and then Text (Q - 1) /= ' '
                 and then Q2 < PE and then Text (Q2) /= ' '
               then
                  Add (Q - 1, Q2,
                       Add_Sat (Add_Kern (X, Text_Metrics.Kern
                                            (T, Prev, Character'Pos ('-'))),
                                Hyphen_W),
                       Hyphen_Penalty, True, True);
               end if;
            else
               K := Text_Metrics.Kern (T, Prev, C);
               if Breaks_Between (Prev, C) then
                  Add (Q - 1, Q, X, 0, False, False);
               end if;
               --  The lines after pending breaks start here, without the
               --  kerning with the character before.
               if Pend > 0 then
                  for B in Pend .. N loop
                     W.Brk (B).Start_W := Add_Kern (X, K);
                     W.Brk (B).Start_Sp := Sp;
                  end loop;
                  Pend := 0;
               end if;
               if not Hyphenation.Is_Letter (C) then
                  In_Run := False;
                  Run_N := 0;
               elsif not In_Run then
                  In_Run := True;
                  Run_I := 0;
                  Run_N := 0;
                  if Hyph then
                     Word_Points (G.Hyph.all, Text, Q, PE, Points, Run_N);
                  end if;
               end if;
               if In_Run and then Run_I < Natural'Last then
                  Run_I := Run_I + 1;
               end if;
               X := Add_Sat (Add_Kern (X, K), Text_Metrics.Advance (T, F, C));
               Prev := C;
               if Breaks_After (C) and then Q > PS
                 and then Text (Q - 1) /= ' '
                 and then Q2 < PE and then Text (Q2) /= ' '
               then
                  Add (Q2 - 1, Q2, X, Hyphen_Penalty, False, True);
               elsif In_Run and then Run_I < Run_N
                 and then Run_I in Points'Range and then Points (Run_I)
               then
                  Add (Q2 - 1, Q2,
                       Add_Sat (Add_Kern (X, Text_Metrics.Kern
                                            (T, C, Character'Pos ('-'))),
                                Hyphen_W),
                       Hyphen_Penalty, True, True);
               end if;
            end if;
         end if;
         Q := Q2;
      end loop;

      --  The paragraph's end: its last line takes everything left.
      Push (PE - 1, (if PE > Text'Last then PE else PE + 1), X, 0,
            False, False);
      if N = 0 then
         Ok := False;
      end if;
   end Scan_Paragraph;

   --  Choose the cheapest set of W.Brk (0 .. N) with no line worse than
   --  Tolerance, and chain it through Succ from W.Brk (0).  Found is False
   --  when there is none: some word does not fit, or (below Natural'Last)
   --  every set has a line that is too loose.
   procedure Choose
     (G         : Geometry;
      Space_W   : Natural;
      N         : Positive;
      Tolerance : Natural;
      W         : in out Workspace;
      Found     : out Boolean)
     with Pre => N <= Max_Breaks
   is
      Sp_W    : constant Px := Natural'Min (Space_W, Max_Px);
      Stretch : constant Natural := Stretch_Of (Sp_W);
      Shrink  : constant Natural := Shrink_Of (Sp_W);
      Budget  : Natural;
      Wd, Sps : Natural;
      Cap     : Long_Long_Integer;
      Bad     : Natural;
      Fit     : Fitness;
      D       : Demerits;
      Total   : Demerits;
      Best    : Fitness := Decent;
      J, I    : Natural;
      J_Fit   : Fitness;
   begin
      Found := False;
      for Jx in 1 .. N loop
         W.Brk (Jx).Cost := (others => Infinite);
         for Ix in reverse 0 .. Jx - 1 loop
            Budget :=
              (if Ix = 0 then Diff (G.Col_Width, G.Indent) else G.Col_Width);
            Wd := Diff (W.Brk (Jx).End_W, W.Brk (Ix).Start_W);
            Sps := Diff (W.Brk (Jx).End_Sp, W.Brk (Ix).Start_Sp);
            if Wd > Budget then
               --  Shrink the spaces, as far as they go; lines starting
               --  earlier only get longer.
               Cap := Long_Long_Integer (Sps) * Long_Long_Integer (Shrink);
               exit when Long_Long_Integer (Wd - Budget) > Cap;
               Bad := Badness (Natural'Min (Wd - Budget, Max_Px), Cap);
               Fit := (if Bad > 12 then Tight else Decent);
            elsif Jx = N then
               --  The last line is not justified.
               Bad := 0;
               Fit := Decent;
            else
               Cap := Long_Long_Integer (Sps) * Long_Long_Integer (Stretch);
               Bad := Badness (Natural'Min (Budget - Wd, Max_Px), Cap);
               Fit := (if Bad > 99 then Very_Loose
                       elsif Bad > 12 then Loose
                       else Decent);
            end if;
            if Bad <= Tolerance then
               D := Demerits (Line_Penalty + Bad) ** 2;
               if W.Brk (Jx).Penalty > 0 then
                  D := Add_Cost
                    (D, Demerits (Natural'Min (W.Brk (Jx).Penalty, 2**15))
                        ** 2);
               end if;
               if W.Brk (Ix).Flagged then
                  D := Add_Cost
                    (D, (if Jx = N then Final_Hyphen
                         elsif W.Brk (Jx).Flagged then Double_Hyphen
                         else 0));
               end if;
               for PF in Fitness loop
                  if W.Brk (Ix).Cost (PF) < Infinite then
                     Total := Add_Cost
                       (Add_Cost (W.Brk (Ix).Cost (PF), D),
                        (if abs (Fitness'Pos (PF) - Fitness'Pos (Fit)) > 1
                         then Adjacent else 0));
                     if Total < W.Brk (Jx).Cost (Fit) then
                        W.Brk (Jx).Cost (Fit) := Total;
                        W.Brk (Jx).From (Fit) := Ix;
                        W.Brk (Jx).From_Fit (Fit) := PF;
                     end if;
                  end if;
               end loop;
            end if;
         end loop;
      end loop;

      for PF in Fitness loop
         if W.Brk (N).Cost (PF) < W.Brk (N).Cost (Best) then
            Best := PF;
         end if;
      end loop;
      if W.Brk (N).Cost (Best) = Infinite then
         return;
      end if;

      --  Chain the chosen breaks forward.
      J := N;
      J_Fit := Best;
      while J > 0 loop
         pragma Loop_Invariant (J <= N);
         pragma Loop_Variant (Decreases => J);
         I := W.Brk (J).From (J_Fit);
         if I >= J then
            return;   --  not a set: never, as From < J
         end if;
         W.Brk (I).Succ := J;
         J_Fit := W.Brk (J).From_Fit (J_Fit);
         J := I;
      end loop;
      Found := True;
   end Choose;

   --  Set the paragraph Text (PS .. PE - 1) into W: W.Optimal when it could
   --  be set as a whole, else it is to be set greedily.
   procedure Set_Paragraph
     (T      : Text_Metrics.Table;
      F      : Truetype.Font;
      G      : Geometry;
      Text   : String;
      PS, PE : Positive;
      W      : in out Workspace)
     with Pre  => Text'First = 1 and then Text'Last < Positive'Last
                  and then PS <= PE and then PE <= Text'Last + 1,
          Post => W.Cached and then W.Para_First = PS
   is
      Space_W : constant Natural :=
        Text_Metrics.Advance (T, F, Character'Pos (' '));
      N       : Natural;
      Ok      : Boolean;
      Found   : Boolean := False;
   begin
      W.Optimal := False;
      W.Count := 0;
      Scan_Paragraph (T, F, G, Text, PS, PE, False, W, N, Ok);
      if Ok then
         Choose (G, Space_W, N, Pretolerance, W, Found);
      end if;
      if not Found and then G.Hyph /= null then
         Scan_Paragraph (T, F, G, Text, PS, PE, True, W, N, Ok);
      end if;
      if not Found and then Ok then
         Choose (G, Space_W, N, Natural'Last, W, Found);
      end if;
      if Found then
         W.Optimal := True;
         W.Count := N;
      end if;
      W.Cached := True;
      W.Para_First := PS;
   end Set_Paragraph;

   --  Page_Lines, keeping the paragraph W holds when W.Cached says it is
   --  for Text.
   procedure Fill_Page
     (T     : Text_Metrics.Table;
      F     : Truetype.Font;
      G     : Geometry;
      Text  : String;
      Start : Positive;
      W     : in out Workspace;
      Count : out Positive)
     with Pre  => Text'First = 1 and then Text'Last < Positive'Last
                  and then Start <= Text'Last,
          Post => Count <= Max_Page_Lines
                  and then W.Lines (Count).Next in Start + 1 .. Text'Last + 1
   is
      P      : Positive := Start;
      PS, PE : Positive;
      Y      : Natural := 0;
      I, J   : Natural;
      Steps  : Natural;
      Chain  : Boolean;
      L      : Line;
      N      : Natural := 0;
      Full   : Boolean;
   begin
      Count := 1;
      loop
         pragma Loop_Invariant (P in Start .. Text'Last);
         pragma Loop_Invariant (N < Max_Page_Lines);
         pragma Loop_Invariant (if N > 0 then Count = N);
         pragma Loop_Invariant (Y <= G.Area_Height);
         pragma Loop_Variant (Increases => P);

         --  The paragraph P is in.
         PS := P;
         while PS > 1 and then Text (PS - 1) /= LF loop
            pragma Loop_Invariant (PS in 2 .. P);
            pragma Loop_Variant (Decreases => PS);
            PS := PS - 1;
         end loop;
         PE := P;
         while PE <= Text'Last and then Text (PE) /= LF loop
            pragma Loop_Invariant (PE in P .. Text'Last);
            pragma Loop_Variant (Increases => PE);
            PE := PE + 1;
         end loop;
         if not (W.Cached and then W.Para_First = PS) then
            Set_Paragraph (T, F, G, Text, PS, PE, W);
         end if;

         --  The chosen line starting at P, if P starts one.
         Chain := False;
         I := 0;
         if W.Optimal then
            Steps := 0;
            while Steps <= W.Count loop
               pragma Loop_Invariant (I <= Max_Breaks);
               pragma Loop_Variant (Increases => Steps);
               if W.Brk (I).Next = P then
                  Chain := True;
                  exit;
               end if;
               exit when W.Brk (I).Succ not in I + 1 .. W.Count;
               I := W.Brk (I).Succ;
               Steps := Steps + 1;
            end loop;
         end if;

         --  The paragraph's lines from P on, as far as the page goes.
         loop
            pragma Loop_Invariant (P in P'Loop_Entry .. Text'Last);
            pragma Loop_Invariant (P >= Start);
            pragma Loop_Invariant (N < Max_Page_Lines);
            pragma Loop_Invariant (if N > 0 then Count = N);
            pragma Loop_Invariant (Y <= G.Area_Height);
            pragma Loop_Invariant (I <= Max_Breaks);
            pragma Loop_Variant (Increases => P);
            if Chain and then W.Brk (I).Succ in I + 1 .. W.Count then
               J := W.Brk (I).Succ;
               L := (First    => P,
                     Last     => W.Brk (J).Last,
                     Next     => W.Brk (J).Next,
                     Width    => Diff (W.Brk (J).End_W, W.Brk (I).Start_W),
                     Spaces   => Diff (W.Brk (J).End_Sp, W.Brk (I).Start_Sp),
                     Indented => I = 0,
                     Para_End => J = W.Count,
                     Hyphen   => W.Brk (J).Hyphen);
               I := J;
            else
               Chain := False;
               L.Next := P;
            end if;
            if not (L.Next > P and then L.Next <= Text'Last + 1
                    and then L.Last <= Text'Last)
            then
               --  Greedily, when the paragraph could not be set as a whole
               --  or P does not start a line of its set.
               Chain := False;
               Break_Line (T, F, G, Text, P, L);
            end if;
            N := N + 1;
            Count := N;
            W.Lines (N) := L;
            P := L.Next;
            Y := Y + G.Line_Height + (if L.Para_End then G.Para_Gap else 0);
            Full := P > Text'Last or else N = Max_Page_Lines
                    or else Y + G.Line_Height > G.Area_Height;
            exit when Full or else L.Para_End;
         end loop;
         exit when Full;
      end loop;
   end Fill_Page;

   procedure Page_Lines
     (T     : Text_Metrics.Table;
      F     : Truetype.Font;
      G     : Geometry;
      Text  : String;
      Start : Positive;
      W     : in out Workspace;
      Count : out Positive) is
   begin
      --  What W holds may be for another text.
      W.Cached := False;
      Fill_Page (T, F, G, Text, Start, W, Count);
   end Page_Lines;

   procedure Paginate
     (T        : Text_Metrics.Table;
      F        : Truetype.Font;
      G        : Geometry;
      Text     : String;
      W        : in out Workspace;
      Starts   : out Offset_Array;
      Count    : out Natural;
      Complete : out Boolean)
   is
      P : Positive := 1;
      N : Positive;
   begin
      for I in Starts'Range loop   --  not an aggregate: see Glyph_Cache
         Starts (I) := 1;
      end loop;
      Count := 0;
      Complete := True;
      W.Cached := False;
      while P <= Text'Last loop
         pragma Loop_Invariant (Count <= Starts'Last);
         pragma Loop_Variant (Increases => P);
         if Count = Starts'Last then
            Complete := False;
            return;
         end if;
         Count := Count + 1;
         Starts (Count) := P;
         Fill_Page (T, F, G, Text, P, W, N);
         P := W.Lines (N).Next;
      end loop;
   end Paginate;

   function Page_Of
     (Starts : Offset_Array; Count : Positive; Offset : Positive)
      return Positive
   is
      Lo : Positive := 1;
      Hi : Positive := Count;
      Mid : Positive;
   begin
      --  The last page whose start is at or before Offset.
      while Lo < Hi loop
         pragma Loop_Invariant (Lo <= Hi and then Hi <= Count);
         pragma Loop_Variant (Decreases => Hi - Lo);
         Mid := Lo + (Hi - Lo + 1) / 2;
         if Starts (Mid) <= Offset then
            Lo := Mid;
         else
            Hi := Mid - 1;
         end if;
      end loop;
      return Lo;
   end Page_Of;

end Page_Layout;
