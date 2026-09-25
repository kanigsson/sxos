--  sxos: the Library screen.  Mount the card, list /Books, load a font face
--  from /Fonts into PSRAM, and let the user move a selection with the nav
--  buttons or pick a book by touch; tapping the selected book opens it
--  (logged only until the Reader, M5).  The first screen is a full refresh;
--  selection changes are fast (DU) updates.
with Ada.Real_Time; use Ada.Real_Time;
with Interfaces; use Interfaces;
with System.BB.CPU_Primitives.Multiprocessors;
with ESP32S3.Log; use ESP32S3.Log;
with ESP32S3.GPIO;

with Interfaces.C;

with App_State;
with Bitmap_Text;
with Book_Source;
with Card;
with Card_Scan;
with Font_Catalog;
with Font_Loader;
with Gauge;
with Library_View;
with Mono_Frame;
with Shelf;
with Status_Bar;
with Truetype;
with X4_Display;
with X4_Touch;

pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package FS renames Card.FS;
   package Scan is new Card_Scan (FS);
   use type FS.Mount_Status;
   use type Scan.Scan_Status;

   --  X4 Pro nav keys: plain active-low buttons with internal pull-ups.
   --  Left is up/previous, Right is down/next.
   Left_Pin  : constant ESP32S3.GPIO.Pin_Id := 0;
   Right_Pin : constant ESP32S3.GPIO.Pin_Id := 7;

   Screen   : Mono_Frame.Frame renames App_State.Screen;
   Volume   : FS.Volume renames App_State.Volume;
   Books    : Shelf.List renames App_State.Books.all;
   Faces    : Font_Catalog.List renames App_State.Faces;
   Font     : Truetype.Font;
   Have_Font : Boolean := False;
   Selected : Natural := 0;
   Touch_OK : Boolean;

   function Ms_Since (T : Time) return Integer is
     (Integer (To_Duration (Clock - T) * 1000.0));

   package Fonts is new Font_Loader (FS, Scan.Fonts_Folder);
   package Book_Files is new Book_Source (FS, Scan.Books_Folder);
   use type Book_Files.Status;
   Current : Book_Files.Book;

   function Heap_Free return Interfaces.C.size_t
     with Import, Convention => C, External_Name => "__bare_heap_free_bytes";

   --  Milestone M4: open the book and load its first chapters, logging
   --  sizes and times.  The reader screen arrives with M5.
   procedure Open_Book (I : Shelf.Index) is
      T0     : Time := Clock;
      Result : Book_Files.Status;
      Shown  : Boolean := False;
   begin
      Book_Files.Open (Volume, Shelf.Name (Books, I), Current, Result);
      Put ("[book] open " & Shelf.Name (Books, I) & ": " & Result'Image & ",");
      Put (Book_Files.Chapter_Count (Current));
      Put (" chapters in ");
      Put (Ms_Since (T0));
      Put_Line (" ms");
      if Result /= Book_Files.OK then
         return;
      end if;
      for C in 1 .. Natural'Min (Book_Files.Chapter_Count (Current), 6) loop
         T0 := Clock;
         Book_Files.Load (Volume, Current, C, Result);
         Put ("[book]   chapter");
         Put (C);
         Put (": " & Result'Image & ",");
         Put (Book_Files.Text_Last (Current));
         Put (" bytes of text in ");
         Put (Ms_Since (T0));
         Put (" ms, heap free ");
         Put (Integer (Heap_Free) / 1024);
         Put_Line (" KB");
         if Result = Book_Files.OK and then not Shown
           and then Book_Files.Text_Last (Current) > 0
         then
            declare
               T : String renames Book_Files.Text (Current).all;
               L : Natural := Natural'Min (Book_Files.Text_Last (Current), 200);
            begin
               --  Cut at a UTF-8 character boundary.
               while L > 0 and then L < Book_Files.Text_Last (Current)
                 and then Character'Pos (T (L + 1)) in 16#80# .. 16#BF#
               loop
                  L := L - 1;
               end loop;
               Put_Line ("[book]   | " & T (1 .. L));
            end;
            Shown := True;
         end if;
      end loop;
   end Open_Book;

   procedure Load_Font (Face : Font_Catalog.Index) is
      T0 : constant Time := Clock;
   begin
      Fonts.Load (Volume, Faces, Face, Font, Have_Font);
      Put ("[font] " & Font_Catalog.File_Name (Faces, Face) & ": ");
      Put (Integer (Faces.Faces (Face).Size));
      Put (" bytes in ");
      Put (Ms_Since (T0));
      Put_Line (if Have_Font then " ms" else " ms, but it did not load");
   end Load_Font;

   --  A screen for when there is no usable font: the 5x7 fallback.
   procedure Show_Problem (Line_1, Line_2 : String) is
   begin
      Mono_Frame.Clear (Screen);
      Bitmap_Text.Draw (Screen, 24, 360, Line_1, Scale => 3);
      Bitmap_Text.Draw (Screen, 24, 400, Line_2, Scale => 2);
      X4_Display.Show (Screen);
   end Show_Problem;

   procedure Render is
      T0 : constant Time := Clock;
      B  : Status_Bar.Battery;
   begin
      B := Gauge.Read;
      Library_View.Draw (Screen, Font, Books, Selected, B);
      Put ("[sxos] library drawn in ");
      Put (Ms_Since (T0));
      Put_Line (" ms");
      X4_Display.Show (Screen);
   end Render;

   procedure Set_Selection (I : Natural) is
   begin
      if I in 1 .. Books.Count and then I /= Selected then
         Selected := I;
         Put_Line ("[sxos] selected: " & Shelf.Name (Books, Selected));
         Render;
      end if;
   end Set_Selection;

   --  Debounced, edge-triggered button scan at a fixed poll cadence.
   type Button_State is record
      Pressed : Boolean := False;
      Ticks   : Natural := 0;
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

   Status      : FS.Mount_Status;
   Scan_Result : Scan.Scan_Status;
   Card_Ok     : Boolean;

begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[sxos] bare-metal Ada Xteink X4 Pro reader");
   --  Display, SD card and touch all share the board peripheral rail, which
   --  X4_Display.Initialize raises.  The gauge shares the touch I2C bus.
   X4_Display.Initialize;
   X4_Touch.Initialize (Touch_OK);
   Gauge.Initialize;

   Card.Initialize (Card_Ok);
   if not Card_Ok then
      Show_Problem ("No SD card", "Insert a FAT32 card and restart.");
      loop
         delay until Clock + Seconds (60);
      end loop;
   end if;

   FS.Mount (Volume, Status);
   Put_Line ("[card] mount: " & Status'Image);
   if Status /= FS.OK then
      Show_Problem ("Card not readable", "Mount: " & Status'Image);
      loop
         delay until Clock + Seconds (60);
      end loop;
   end if;

   Scan.Scan_Fonts (Volume, Faces, Scan_Result);
   Put ("[card] fonts: " & Scan_Result'Image & ",");
   Put (Integer (Faces.Count));
   Put_Line (" regular faces");
   for I in 1 .. Faces.Count loop
      Put_Line ("[card]   " & Font_Catalog.File_Name (Faces, I));
   end loop;
   if Font_Catalog.Default (Faces) /= 0 then
      Load_Font (Font_Catalog.Default (Faces));
   end if;
   if not Have_Font then
      Show_Problem ("No usable font", "Put a TrueType .ttf into /Fonts.");
      loop
         delay until Clock + Seconds (60);
      end loop;
   end if;

   Scan.Scan_Books (Volume, Books, Scan_Result);
   Put ("[card] books: " & Scan_Result'Image & ",");
   Put (Integer (Books.Count));
   Put_Line (" found");
   Selected := (if Books.Count > 0 then 1 else 0);

   ESP32S3.GPIO.Configure (Left_Pin, ESP32S3.GPIO.Input, ESP32S3.GPIO.Pull_Up);
   ESP32S3.GPIO.Configure (Right_Pin, ESP32S3.GPIO.Input, ESP32S3.GPIO.Pull_Up);

   Render;
   Put_Line ("[sxos] library shown; awaiting input");

   loop
      delay until Clock + Milliseconds (20);
      Scan_Button (Left, Left_Pin, -1);
      Scan_Button (Right, Right_Pin, 1);

      declare
         TX, TY  : Natural;
         Contact : Boolean;
         Hit     : Natural;
      begin
         X4_Touch.Read_Contact (TX, TY, Contact);
         if Contact then
            Hit := Library_View.Book_At (Font, Books, Selected, TY);
            if Hit /= 0 and then Hit = Selected then
               Open_Book (Hit);
            else
               Set_Selection (Hit);
            end if;
         end if;
      end;
   end loop;
end Main;
