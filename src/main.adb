--  Read the SD card's /Books directory and display one portrait page.
with Ada.Real_Time; use Ada.Real_Time;
with System.BB.CPU_Primitives.Multiprocessors;
with ESP32S3.Log; use ESP32S3.Log;
with X4_Display;
with Books_List;

pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   use type Books_List.Result_Kind;
   Items  : Books_List.Entries;
   Count  : Natural;
   Result : Books_List.Result_Kind;
begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[sxos] bare-metal Ada Xteink X4 Pro bring-up");
   --  The display and SD card share the board peripheral rail (GPIO1).
   X4_Display.Initialize;
   Books_List.Load (Items, Count, Result);
   Put_Line ("[sxos] Books: " & Books_List.Result_Kind'Image (Result));

   X4_Display.Clear;
   X4_Display.Draw_Line (24, 26, "Books / ");
   if Result = Books_List.OK then
      for I in 1 .. Count loop
         X4_Display.Draw_Line
           (24, 78 + (I - 1) * 40,
            (if Items (I).Directory then "> " else "  ") &
            Items (I).Text (1 .. Items (I).Last));
      end loop;
   else
      X4_Display.Draw_Line (24, 78, Books_List.Result_Kind'Image (Result));
   end if;
   X4_Display.Show;
   Put_Line ("[sxos] portrait Books frame submitted; idling");
   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
