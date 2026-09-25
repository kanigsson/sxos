with Text_Raster;
with UTF8;

package body Page_Layout
  with SPARK_Mode => On
is
   use type UTF8.Code_Point;

   LF : constant Character := ASCII.LF;

   function Make
     (T : Text_Metrics.Table; F : Truetype.Font;
      Col_Width, Area_Height : Positive) return Geometry
   is
      Size : constant Positive := Text_Metrics.Size (T);
      Asc  : constant Natural := Text_Raster.Ascent_Px (F, Size);
      Desc : constant Natural := Text_Raster.Descent_Px (F, Size);
      --  About 1.35 em from baseline to baseline, or the face's own line
      --  spacing when that is looser.
      LH   : constant Positive :=
        Positive'Max (Text_Raster.Line_Height_Px (F, Size),
                      (Size * 135 + 50) / 100);
   begin
      return (Size        => Size,
              Col_Width   => Col_Width,
              Area_Height => Area_Height,
              Line_Height => LH,
              Ascent      => Asc + (LH - Asc - Desc) / 2,
              Indent      => Size * 3 / 2,
              Para_Gap    => LH / 4);
   end Make;

   --  A code point after which a line may break inside a word: hyphen,
   --  hyphen (U+2010), en and em dash, zero-width space.
   function Breaks_After (C : UTF8.Code_Point) return Boolean is
     (C = Character'Pos ('-') or else C = 16#2010# or else C = 16#2013#
      or else C = 16#2014# or else C = 16#200B#);

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

      Q      : Positive := From;
      Q2     : Positive;
      C      : UTF8.Code_Point;
      A      : Natural;
      W      : Natural := 0;
      Spaces : Natural := 0;

      --  The latest place the line could end: its last byte, where the
      --  next line would start, its width and its spaces.
      Have_Break : Boolean := False;
      B_Last     : Natural := 0;
      B_Next     : Positive := From;
      B_Width    : Natural := 0;
      B_Spaces   : Natural := 0;
   begin
      L := (First    => From,
            Last     => From - 1,
            Next     => From + 1,
            Width    => 0,
            Spaces   => 0,
            Indented => Indented,
            Para_End => True);

      loop
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
            end if;
            Q2 := Q + 1;
            B_Next := Q2;
            Spaces := Spaces + 1;
            W := W + Space_W;
         else
            Q2 := Q;
            UTF8.Next_Code (Text, Q2, C);
            A := Text_Metrics.Advance (T, F, C);
            if W + A > Budget and then Q > From then
               exit;
            end if;
            W := W + A;
            if Breaks_After (C) and then Q > From and then Text (Q - 1) /= ' '
              and then Q2 <= Text'Last and then Text (Q2) /= ' '
              and then Text (Q2) /= LF
            then
               Have_Break := True;
               B_Last := Q2 - 1;
               B_Next := Q2;
               B_Width := W;
               B_Spaces := Spaces;
            end if;
         end if;
         Q := Q2;
      end loop;

      --  The code point at Q overflows the column.
      L.Para_End := False;
      if Have_Break then
         L.Last := B_Last;
         L.Next := B_Next;
         L.Width := B_Width;
         L.Spaces := B_Spaces;
      else
         L.Last := Q - 1;
         L.Next := Q;
         L.Width := W;
         L.Spaces := Spaces;
      end if;

      --  A break at a space starts the next line after the space(s).
      while L.Next <= Text'Last and then Text (L.Next) = ' ' loop
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
