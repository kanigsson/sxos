with Text_Raster;

package body Sleep_View
  with SPARK_Mode => On
is
   procedure Draw
     (Fr    : in out Mono_Frame.Frame;
      UI    : Truetype.Font;
      Title : String;
      Batt  : Status_Bar.Battery)
   is
      Mid : constant := Mono_Frame.Height / 2;
   begin
      Mono_Frame.Clear (Fr);
      Status_Bar.Draw (Fr, UI, Title, Batt);
      Mono_Frame.Frame_Rect (Fr, 32, Mid - 90, Mono_Frame.Width - 64, 150);
      Mono_Frame.Frame_Rect (Fr, 33, Mid - 89, Mono_Frame.Width - 66, 148);
      Text_Raster.Draw_Centered
        (Fr, UI, 40, 0, Mono_Frame.Width, Mid - 10, "Sleeping");
      Text_Raster.Draw_Centered
        (Fr, UI, 22, 0, Mono_Frame.Width, Mid + 34,
         "Press the power button to wake");
   end Draw;
end Sleep_View;
