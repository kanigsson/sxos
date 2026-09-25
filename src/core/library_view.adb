with Text_Raster;

package body Library_View
  with SPARK_Mode => On
is
   Margin   : constant := 16;
   Top      : constant := Status_Bar.Height + 8;
   Footer   : constant := 60;
   Pad      : constant := 18;   --  vertical padding inside a row
   Foot_Size : constant := 22;

   --  The Settings button, at the right of the footer.
   Set_W : constant := 150;
   Set_H : constant := 46;
   Set_X : constant := Mono_Frame.Width - Margin - Set_W;
   Set_Y : constant := Mono_Frame.Height - Footer + (Footer - Set_H) / 2;

   function Settings_At (X, Y : Integer) return Boolean is
     (X in Set_X - 8 .. Set_X + Set_W + 7
      and then Y in Set_Y - 8 .. Mono_Frame.Height - 1);

   --  The page arrows, either side of the page number, left of Settings.
   Arrow_W  : constant := 56;
   Prev_X   : constant := Margin;
   Next_X   : constant := Set_X - 24 - Arrow_W;
   Number_L : constant := Prev_X + Arrow_W;
   Number_R : constant := Next_X;

   function Page_Step_At (X, Y : Integer) return Integer is
     (if Y not in Set_Y - 8 .. Mono_Frame.Height - 1 then 0
      elsif X in Prev_X - 8 .. Prev_X + Arrow_W + 7 then -1
      elsif X in Next_X - 8 .. Next_X + Arrow_W + 7 then 1
      else 0);

   --  A solid triangle centred in the arrow box at X, pointing left or right.
   procedure Arrow (Fr : in out Mono_Frame.Frame; X : Integer; Left : Boolean)
     with Pre => X in 0 .. Mono_Frame.Width
   is
      Half : constant := 10;
      CX   : constant Integer := X + Arrow_W / 2;
      CY   : constant Integer := Set_Y + Set_H / 2;
      W    : Natural;
   begin
      Mono_Frame.Frame_Rect (Fr, X, Set_Y, Arrow_W, Set_H);
      for Row in -Half .. Half loop
         W := Half - abs Row;
         Mono_Frame.Fill_Rect
           (Fr, CX - Half / 2 + (if Left then Half - W else 0), CY + Row,
            W + 1, 1);
      end loop;
   end Arrow;

   function Pitch (F : Truetype.Font) return Positive is
     (Text_Raster.Line_Height_Px (F, Name_Size) + Pad);

   function Rows_Per_Page (F : Truetype.Font) return Positive is
     (Positive'Max (1, (Mono_Frame.Height - Top - Footer) / Pitch (F)));

   --  First book index on the page that shows Selected.
   function Page_First (F : Truetype.Font; Selected : Natural)
     return Positive
   is
     (if Selected = 0 then 1
      else ((Selected - 1) / Rows_Per_Page (F)) * Rows_Per_Page (F) + 1);

   function Page_Target
     (F : Truetype.Font; L : Shelf.List; Selected : Natural; Step : Integer)
      return Natural
   is
      First : constant Positive := Page_First (F, Selected);
      Rows  : constant Positive := Rows_Per_Page (F);
   begin
      if Step > 0 and then First <= L.Count - Rows then
         return First + Rows;
      elsif Step < 0 and then First > Rows then
         return First - Rows;
      else
         return Selected;
      end if;
   end Page_Target;

   function Book_At
     (F : Truetype.Font; L : Shelf.List; Selected : Natural; Y : Integer)
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
      return (if First <= L.Count - Row then First + Row else 0);
   end Book_At;

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
      L        : Shelf.List;
      Selected : Natural;
      Batt     : Status_Bar.Battery;
      Message  : String := "No books in /Books")
   is
      Rows  : constant Positive := Rows_Per_Page (F);
      First : constant Positive := Page_First (F, Selected);
      P     : constant Positive := Pitch (F);
      Asc   : constant Natural := Text_Raster.Ascent_Px (F, Name_Size);
      Desc  : constant Natural := Text_Raster.Descent_Px (F, Name_Size);
      Max_W : constant := Mono_Frame.Width - 2 * Margin;
      Ellipsis : constant String := "...";
      --  The page's last book (First + Rows - 1, or the list's last).
      Last  : constant Natural :=
        (if L.Count - First < Rows then L.Count else First + Rows - 1);
   begin
      Mono_Frame.Clear (Fr);
      Status_Bar.Draw (Fr, F, Title, Batt);

      Mono_Frame.Frame_Rect (Fr, Set_X, Set_Y, Set_W, Set_H);
      Text_Raster.Draw_Centered
        (Fr, F, Foot_Size, Set_X, Set_X + Set_W,
         Set_Y + (Set_H + Text_Raster.Ascent_Px (F, Foot_Size)
                  - Text_Raster.Descent_Px (F, Foot_Size)) / 2,
         "Settings");

      if L.Count = 0 then
         Text_Raster.Draw_Centered
           (Fr, F, Name_Size, 0, Mono_Frame.Width, Mono_Frame.Height / 2,
            Message);
         return;
      end if;

      for I in First .. Last loop
         declare
            Y        : constant Integer := Top + (I - First) * P;
            Baseline : constant Integer := Y + (P + Asc - Desc) / 2;
            T        : constant String := Shelf.Title (L, I);
            Sel      : constant Boolean := I = Selected;
            Cut      : Natural;
         begin
            if Sel then
               Mono_Frame.Fill_Rect (Fr, 0, Y, Mono_Frame.Width, P);
            end if;
            if Text_Raster.Width (F, Name_Size, T) <= Max_W then
               Text_Raster.Draw_Text
                 (Fr, F, Name_Size, Margin, Baseline, T, Black => not Sel);
            else
               Cut := Text_Raster.Fit
                 (F, Name_Size, T,
                  Natural'Max
                    (0, Max_W - Text_Raster.Width (F, Name_Size, Ellipsis)));
               Text_Raster.Draw_Text
                 (Fr, F, Name_Size, Margin, Baseline,
                  T (T'First .. Cut) & Ellipsis, Black => not Sel);
            end if;
         end;
      end loop;

      if L.Count > Rows then
         Arrow (Fr, Prev_X, Left => True);
         Arrow (Fr, Next_X, Left => False);
         Text_Raster.Draw_Centered
           (Fr, F, Foot_Size, Number_L, Number_R,
            Set_Y + (Set_H + Text_Raster.Ascent_Px (F, Foot_Size)
                     - Text_Raster.Descent_Px (F, Foot_Size)) / 2,
            Image ((First - 1) / Rows + 1) & " / "
            & Image ((L.Count + Rows - 1) / Rows));
      end if;
   end Draw;

end Library_View;
