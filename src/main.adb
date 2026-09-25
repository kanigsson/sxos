--  Read the SD card's /Books directory, list it, and let the user move a
--  selection highlight with the left/right nav buttons or a touch on the
--  panel.  Every selection change redraws the portrait frame and refreshes
--  the e-paper (a full UC8279 refresh, so each move takes a few seconds).
with Ada.Real_Time; use Ada.Real_Time;
with System.BB.CPU_Primitives.Multiprocessors;
with ESP32S3.Log; use ESP32S3.Log;
with ESP32S3.GPIO;
with X4_Display;
with X4_Touch;
with Books_List;

pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   use type Books_List.Result_Kind;

   --  X4 Pro nav keys (hardware-confirmed FreeInk profile): plain active-low
   --  buttons with internal pull-ups.  Left is Up/previous, Right Down/next.
   Left_Pin  : constant ESP32S3.GPIO.Pin_Id := 0;
   Right_Pin : constant ESP32S3.GPIO.Pin_Id := 7;

   --  Portrait list layout for the scaled 5x7 font (14 px tall at scale 2).
   Row_Base  : constant := 78;    --  first entry's text top, portrait Y
   Row_Pitch : constant := 40;   --  one entry row
   Bar_X     : constant := 10;   --  highlight bar geometry
   Bar_W     : constant := 460;
   Bar_H     : constant := Row_Pitch;

   Items    : Books_List.Entries;
   Count    : Natural;
   Result   : Books_List.Result_Kind;
   Touch_OK : Boolean;
   Selected : Natural := 1;

   function Entry_Text (I : Positive) return String is
   begin
      return (if Items (I).Directory then "> " else "  ")
        & Items (I).Text (1 .. Items (I).Last);
   end Entry_Text;

   --  Redraw the whole portrait frame with the current selection, then run
   --  one full e-paper refresh.  This is the screen redraw path: nothing is
   --  partial, so every move of the highlight re-runs it.
   procedure Render_List is
   begin
      X4_Display.Clear;
      X4_Display.Draw_Line (24, 26, "Books / ");
      if Result = Books_List.OK and then Count > 0 then
         for I in 1 .. Count loop
            declare
               Y : constant Natural := Row_Base + (I - 1) * Row_Pitch;
            begin
               if I = Selected then
                  X4_Display.Fill_Rect (Bar_X, Y - 12, Bar_W, Bar_H);
                  X4_Display.Draw_Line (24, Y, Entry_Text (I), Inverted => True);
               else
                  X4_Display.Draw_Line (24, Y, Entry_Text (I));
               end if;
            end;
         end loop;
         X4_Display.Draw_Line
           (24, Row_Base + Count * Row_Pitch + 8, "Left/Right or touch to select");
      else
         X4_Display.Draw_Line (24, Row_Base, Books_List.Result_Kind'Image (Result));
      end if;
      X4_Display.Show;
   end Render_List;

   --  Move the highlight to entry I; 0 or an out-of-range row is a no-op.
   --  A real change redraws the panel and logs the selection.
   procedure Set_Selection (I : Natural) is
   begin
      if I in 1 .. Count and then I /= Selected then
         Selected := I;
         Put ("[sxos] selected ");
         Put (Integer (Selected));
         Put (": ");
         Put_Line (Entry_Text (Selected));
         Render_List;
      end if;
   end Set_Selection;

   --  Which list row covers portrait Y?  0 = none (header/footer areas).
   --  The hit region matches the highlight bar geometry exactly.
   function Row_At (Y : Natural) return Natural is
      Off : constant Integer := Integer (Y) - (Row_Base - 12);
   begin
      if Off < 0 or else Off >= Integer (Count) * Row_Pitch then
         return 0;
      end if;
      return Off / Row_Pitch + 1;
   end Row_At;

   --  Debounced, edge-triggered button scan at a fixed poll cadence.
   type Button_State is record
      Pressed : Boolean := False;  --  debounced level, True = held down
      Ticks   : Natural := 0;      --  consecutive disagreeing samples
   end record;
   Left, Right : Button_State;

   procedure Scan_Button
     (State : in out Button_State; Pin : ESP32S3.GPIO.Pin_Id; Step : Integer)
   is
      Raw : constant Boolean := not ESP32S3.GPIO.Read (Pin);  --  active-low
   begin
      if Raw = State.Pressed then
         State.Ticks := 0;
      else
         State.Ticks := State.Ticks + 1;
         if State.Ticks >= 3 then  --  60 ms of a stable new level
            State.Pressed := Raw;
            State.Ticks := 0;
            if Raw then
               Set_Selection (Integer (Selected) + Step);
            end if;
         end if;
      end if;
   end Scan_Button;

begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[sxos] bare-metal Ada Xteink X4 Pro bring-up");
   --  The display, SD card, and touch all share the board peripheral rail.
   X4_Display.Initialize;
   Books_List.Load (Items, Count, Result);
   Put_Line ("[sxos] Books: " & Books_List.Result_Kind'Image (Result));
   X4_Touch.Initialize (Touch_OK);

   ESP32S3.GPIO.Configure (Left_Pin, ESP32S3.GPIO.Input, ESP32S3.GPIO.Pull_Up);
   ESP32S3.GPIO.Configure (Right_Pin, ESP32S3.GPIO.Input, ESP32S3.GPIO.Pull_Up);

   Render_List;
   Put_Line ("[sxos] Books frame submitted; awaiting input");

   loop
      delay until Clock + Milliseconds (20);
      Scan_Button (Left, Left_Pin, -1);
      Scan_Button (Right, Right_Pin, 1);

      declare
         TX, TY : Natural;
         Contact : Boolean;
      begin
         X4_Touch.Read_Contact (TX, TY, Contact);
         if Contact then
            Put ("[tp] contact at ");
            Put (Integer (TX));
            Put (",");
            Put (Integer (TY));
            Put_Line ("");
            Set_Selection (Row_At (TY));
         end if;
      end;
   end loop;
end Main;
