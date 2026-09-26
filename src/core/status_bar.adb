with Text_Raster;

package body Status_Bar
  with SPARK_Mode => On
is
   Margin : constant := 16;

   --  Battery glyph geometry.
   Body_W : constant := 40;
   Body_H : constant := 20;
   Nub_W  : constant := 4;
   Nub_H  : constant := 8;

   --  P in decimal with a percent sign.  'Image has at most 11 characters;
   --  the bound on the slice says so to the prover.
   function Image (P : Percent) return String
     with Post => Image'Result'First <= 2 and then Image'Result'Length <= 11
   is
      S : constant String := Natural'Image (P);
   begin
      return S (S'First + 1 .. Integer'Min (S'Last, S'First + 10)) & "%";
   end Image;

   procedure Draw_Battery
     (Fr : in out Mono_Frame.Frame; Right, Mid : Integer; Batt : Battery)
   is
      X : constant Integer := Right - Nub_W - Body_W;
      Y : constant Integer := Mid - Body_H / 2;
      Inner : constant := Body_W - 6;
   begin
      Mono_Frame.Frame_Rect (Fr, X, Y, Body_W, Body_H);
      Mono_Frame.Frame_Rect (Fr, X + 1, Y + 1, Body_W - 2, Body_H - 2);
      Mono_Frame.Fill_Rect (Fr, X + Body_W, Mid - Nub_H / 2, Nub_W, Nub_H);
      if Batt.Known then
         Mono_Frame.Fill_Rect
           (Fr, X + 3, Y + 3, (Inner * Batt.Level + 50) / 100, Body_H - 6);
      else
         --  No reading: a question-mark-free "unknown" -- a diagonal slash.
         for K in 0 .. Body_H - 7 loop
            Mono_Frame.Fill_Rect
              (Fr, X + 3 + K * Inner / (Body_H - 6), Y + Body_H - 4 - K, 2, 1);
         end loop;
      end if;
      if Batt.Charging then
         --  A small bolt left of the body.
         Mono_Frame.Fill_Rect (Fr, X - 10, Mid - 8, 3, 8);
         Mono_Frame.Fill_Rect (Fr, X - 8, Mid - 1, 3, 2);
         Mono_Frame.Fill_Rect (Fr, X - 7, Mid, 3, 8);
      end if;
   end Draw_Battery;

   procedure Draw
     (Fr    : in out Mono_Frame.Frame;
      F     : Truetype.Font;
      Title : String;
      Batt  : Battery)
   is
      Mid      : constant := Height / 2;
      Baseline : constant Integer :=
        Mid + (Text_Raster.Ascent_Px (F, Text_Size)
               - Text_Raster.Descent_Px (F, Text_Size)) / 2;
      Right    : constant := Mono_Frame.Width - Margin;
      Batt_X   : constant Integer :=
        Right - Nub_W - Body_W - (if Batt.Charging then 14 else 0);
      Level_X  : constant Integer :=
        (if Batt.Known
         then Batt_X - 8 - Text_Raster.Width (F, Text_Size, Image (Batt.Level))
         else Batt_X);
      Max_W    : constant Integer := Level_X - 16 - Margin;
      Ellipsis : constant String := "...";
      Cut      : Natural;
   begin
      if Text_Raster.Width (F, Text_Size, Title) <= Max_W then
         Text_Raster.Draw_Text (Fr, F, Text_Size, Margin, Baseline, Title);
      elsif Max_W > 0 then
         Cut := Text_Raster.Fit
           (F, Text_Size, Title,
            Natural'Max
              (0, Max_W - Text_Raster.Width (F, Text_Size, Ellipsis)));
         Text_Raster.Draw_Text
           (Fr, F, Text_Size, Margin, Baseline,
            Title (Title'First .. Cut) & Ellipsis);
      end if;
      Draw_Battery (Fr, Right, Mid, Batt);
      if Batt.Known then
         Text_Raster.Draw_Right
           (Fr, F, Text_Size, Batt_X - 8, Baseline, Image (Batt.Level));
      end if;
      Mono_Frame.Fill_Rect (Fr, 0, Height - 2, Mono_Frame.Width, 2);
   end Draw;

end Status_Bar;
