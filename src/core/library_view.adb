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

   function Book_At
     (F : Truetype.Font; L : Shelf.List; Selected : Natural; Y : Integer)
      return Natural
   is
      Off : constant Integer := Y - Top;
      Row : Natural;
      I   : Natural;
   begin
      if Off < 0 or else Off >= Rows_Per_Page (F) * Pitch (F) then
         return 0;
      end if;
      Row := Off / Pitch (F);
      I := Page_First (F, Selected) + Row;
      return (if I <= L.Count then I else 0);
   end Book_At;

   function Image (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Image;

   procedure Draw
     (Fr       : in out Mono_Frame.Frame;
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

      for I in First .. Natural'Min (First + Rows - 1, L.Count) loop
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
                  Max_W - Text_Raster.Width (F, Name_Size, Ellipsis));
               Text_Raster.Draw_Text
                 (Fr, F, Name_Size, Margin, Baseline,
                  T (T'First .. Cut) & Ellipsis, Black => not Sel);
            end if;
         end;
      end loop;

      if L.Count > Rows then
         Text_Raster.Draw_Centered
           (Fr, F, Foot_Size, 0, Mono_Frame.Width,
            Set_Y + (Set_H + Text_Raster.Ascent_Px (F, Foot_Size)
                     - Text_Raster.Descent_Px (F, Foot_Size)) / 2,
            Image ((First - 1) / Rows + 1) & " / "
            & Image ((L.Count + Rows - 1) / Rows));
      end if;
   end Draw;

end Library_View;
