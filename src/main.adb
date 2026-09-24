--  First bring-up application: send a small monochrome "hello" framebuffer
--  through the ESP32-S3 SPI HAL to an EXPERIMENTAL SSD1677-compatible e-paper
--  command set.  The controller and X4 Pro GPIO wiring are NOT yet verified.
with Ada.Real_Time; use Ada.Real_Time;
with System.BB.CPU_Primitives.Multiprocessors;
with ESP32S3.Log; use ESP32S3.Log;
with X4_Display;

pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[sxos] bare-metal Ada Xteink X4 Pro bring-up");
   Put_Line ("[sxos] panel transport is experimental; verify board pinout/controller first");

   X4_Display.Initialize;
   X4_Display.Show_Hello;

   Put_Line ("[sxos] hello frame submitted; idling");
   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
