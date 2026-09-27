with Text_Raster;

package body Toc_View
  with SPARK_Mode => On
is
   Margin    : constant := 16;
   Top       : constant := Status_Bar.Height + 8;
   Footer    : constant := 60;
   Pad       : constant := 14;   --  vertical padding inside a row
   Foot_Size : constant := 22;
   Indent    : constant := 28;   --  per level below the first
   Max_Indents : constant := 3;
   Mark_W    : constant := 6;    --  the "you are here" bar

   --  The Back button, at the right of the footer (the Library's Settings
   --  button).
   Back_W : constant := 150;
   Back_H : constant := 46;
   Back_X : constant := Mono_Frame.Width - Margin - Back_W;
   Back_Y : constant := Mono_Frame.Height - Footer + (Footer - Back_H) / 2;

   function Back_At (X, Y : Integer) return Boolean is
     (X in Back_X - 8 .. Back_X + Back_W + 7
      and then Y in Back_Y - 8 .. Mono_Frame.Height - 1);

   --  The page arrows, either side of the page number, left of Back.
   Arrow_W  : constant := 56;
   Prev_X   : constant := Margin;
   Next_X   : constant := Back_X - 24 - Arrow_W;
   Number_L : constant := Prev_X + Arrow_W;
   Number_R : constant := Next_X;

   function Page_Step_At (X, Y : Integer) return Integer is
     (if Y not in Back_Y - 8 .. Mono_Frame.Height - 1 then 0
      elsif X in Prev_X - 8 .. Prev_X + Arrow_W + 7 then -1
      elsif X in Next_X - 8 .. Next_X + Arrow_W + 7 then 1
      else 0);

   --  A solid triangle centred in the arrow box at X, pointing left or right.
   procedure Arrow (Fr : in out Mono_Frame.Frame; X : Integer; Left : Boolean)
     with Pre => X in 0 .. Mono_Frame.Width
   is
      Half : constant := 10;
      CX   : constant Integer := X + Arrow_W / 2;
      CY   : constant Integer := Back_Y + Back_H / 2;
      W    : Natural;
   begin
      Mono_Frame.Frame_Rect (Fr, X, Back_Y, Arrow_W, Back_H);
      for Row in -Half .. Half loop
         W := Half - abs Row;
         Mono_Frame.Fill_Rect
           (Fr, CX - Half / 2 + (if Left then Half - W else 0), CY + Row,
            W + 1, 1);
      end loop;
   end Arrow;

   function Pitch (F : Truetype.Font) return Positive is
     (Text_Raster.Line_Height_Px (F, Entry_Size) + Pad);

   function Rows_Per_Page (F : Truetype.Font) return Positive is
     (Positive'Max (1, (Mono_Frame.Height - Top - Footer) / Pitch (F)));

   --  First entry on the page that shows Selected.
   function Page_First (F : Truetype.Font; Selected : Natural)
     return Positive
   is
     (if Selected = 0 then 1
      else ((Selected - 1) / Rows_Per_Page (F)) * Rows_Per_Page (F) + 1);

   function Page_Target
     (F : Truetype.Font; Count, Selected : Natural; Step : Integer)
      return Natural
   is
      First : constant Positive := Page_First (F, Selected);
      Rows  : constant Positive := Rows_Per_Page (F);
   begin
      if Step > 0 and then Count >= Rows and then First <= Count - Rows then
         return First + Rows;
      elsif Step < 0 and then First > Rows then
         return First - Rows;
      else
         return Selected;
      end if;
   end Page_Target;

   function Entry_At
     (F : Truetype.Font; Count, Selected : Natural; Y : Integer)
      return Natural
   is
      Off   : Natural;
      Row   : Natural;
      First : Positive;
   begin
      if Y < Top then
         return 0;
      end if;
      Off := Y - Top;
      if Off >= Rows_Per_Page (F) * Pitch (F) then
         return 0;
      end if;
      Row := Off / Pitch (F);
      First := Page_First (F, Selected);
      return (if Count >= Row and then First <= Count - Row
              then First + Row else 0);
   end Entry_At;

   --  N in decimal, without 'Image's leading space.  A Natural's 'Image
   --  has at most 11 characters; the bound on the slice says so to the
   --  prover, so that callers can concatenate the result.
   function Image (N : Natural) return String
     with Post => Image'Result'First = 2 and then Image'Result'Length <= 10
   is
      S : constant String := Natural'Image (N);
   begin
      return S (S'First + 1 .. Integer'Min (S'Last, S'First + 10));
   end Image;

   procedure Draw
     (Fr       : out Mono_Frame.Frame;
      F        : Truetype.Font;
      Title    : String;
      Labels   : String;
      Lines    : Toc.Line_Array;
      Selected : Natural;
      Here     : Natural;
      Batt     : Status_Bar.Battery)
   is
      Count : constant Natural := Lines'Length;
      Rows  : constant Positive := Rows_Per_Page (F);
      First : constant Positive := Page_First (F, Selected);
      P     : constant Positive := Pitch (F);
      Asc   : constant Natural := Text_Raster.Ascent_Px (F, Entry_Size);
      Desc  : constant Natural := Text_Raster.Descent_Px (F, Entry_Size);
      Ellipsis : constant String := "...";
      --  The page's last entry (First + Rows - 1, or the list's last).
      Last  : constant Natural :=
        (if Count < First then 0
         elsif Count - First < Rows then Count else First + Rows - 1);
   begin
      Mono_Frame.Clear (Fr);
      Status_Bar.Draw (Fr, F, Title, Batt);

      Mono_Frame.Frame_Rect (Fr, Back_X, Back_Y, Back_W, Back_H);
      Text_Raster.Draw_Centered
        (Fr, F, Foot_Size, Back_X, Back_X + Back_W,
         Back_Y + (Back_H + Text_Raster.Ascent_Px (F, Foot_Size)
                   - Text_Raster.Descent_Px (F, Foot_Size)) / 2,
         "Back");

      for I in First .. Last loop
         declare
            L        : constant Toc.Line := Lines (I);
            Y        : constant Integer := Top + (I - First) * P;
            Baseline : constant Integer := Y + (P + Asc - Desc) / 2;
            X        : constant Natural :=
              Margin + Mark_W
              + Indent * Natural'Min (L.Level - 1, Max_Indents);
            Max_W    : constant Integer := Mono_Frame.Width - Margin - X;
            T        : constant String :=
              (if L.Last < L.First then "" else Labels (L.First .. L.Last));
            Sel      : constant Boolean := I = Selected;
            Cut      : Natural;
         begin
            if Sel then
               Mono_Frame.Fill_Rect (Fr, 0, Y, Mono_Frame.Width, P);
            end if;
            if I = Here then
               Mono_Frame.Fill_Rect
                 (Fr, 4, Y + Pad / 2, Mark_W, P - Pad, Black => not Sel);
            end if;
            if Text_Raster.Width (F, Entry_Size, T) <= Max_W then
               Text_Raster.Draw_Text
                 (Fr, F, Entry_Size, X, Baseline, T, Black => not Sel);
            else
               Cut := Text_Raster.Fit
                 (F, Entry_Size, T,
                  Natural'Max
                    (0, Max_W - Text_Raster.Width (F, Entry_Size, Ellipsis)));
               Text_Raster.Draw_Text
                 (Fr, F, Entry_Size, X, Baseline,
                  T (T'First .. Cut) & Ellipsis, Black => not Sel);
            end if;
         end;
      end loop;

      if Count > Rows then
         Arrow (Fr, Prev_X, Left => True);
         Arrow (Fr, Next_X, Left => False);
         Text_Raster.Draw_Centered
           (Fr, F, Foot_Size, Number_L, Number_R,
            Back_Y + (Back_H + Text_Raster.Ascent_Px (F, Foot_Size)
                      - Text_Raster.Descent_Px (F, Foot_Size)) / 2,
            Image ((First - 1) / Rows + 1) & " / "
            & Image ((Count - 1) / Rows + 1));
      end if;
   end Draw;

end Toc_View;
