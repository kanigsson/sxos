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

   function Page_End
     (T     : Text_Metrics.Table;
      F     : Truetype.Font;
      G     : Geometry;
      Text  : String;
      Start : Positive) return Positive
   is
      P : Positive := Start;
      Y : Natural := 0;
      L : Line;
   begin
      loop
         pragma Loop_Invariant (P in Start .. Text'Last);
         pragma Loop_Invariant (Y <= G.Area_Height);
         pragma Loop_Variant (Increases => P);
         Break_Line (T, F, G, Text, P, L);
         P := L.Next;
         Y := Y + G.Line_Height + (if L.Para_End then G.Para_Gap else 0);
         exit when P > Text'Last or else Y + G.Line_Height > G.Area_Height;
      end loop;
      return P;
   end Page_End;

   procedure Paginate
     (T        : Text_Metrics.Table;
      F        : Truetype.Font;
      G        : Geometry;
      Text     : String;
      Starts   : out Offset_Array;
      Count    : out Natural;
      Complete : out Boolean)
   is
      P : Positive := 1;
   begin
      for I in Starts'Range loop   --  not an aggregate: see Glyph_Cache
         Starts (I) := 1;
      end loop;
      Count := 0;
      Complete := True;
      while P <= Text'Last loop
         pragma Loop_Invariant (Count <= Starts'Last);
         pragma Loop_Variant (Increases => P);
         if Count = Starts'Last then
            Complete := False;
            return;
         end if;
         Count := Count + 1;
         Starts (Count) := P;
         P := Page_End (T, F, G, Text, P);
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
