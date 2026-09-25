--  sxos: mount the card, list /Books, load a font face from /Fonts into
--  PSRAM, and run the two screens.
--
--  Library: the nav buttons move the selection, a tap selects a book and a
--  tap on the selected one opens it.  Reader: Right or a tap on the right
--  two thirds turns forward, Left or a tap on the left third back; a tap on
--  the top band opens the menu over the page, whose Library button closes
--  the book.  Each book's position is saved to internal flash (Device_Store)
--  when the book is closed and a few seconds after the last page turn, and
--  a book reopens where it was left.  The first screen is a full refresh,
--  opening a book a clean one, and everything else a fast (DU) update.
with Ada.Real_Time; use Ada.Real_Time;
with Interfaces; use Interfaces;
with System.BB.CPU_Primitives.Multiprocessors;
with ESP32S3.Log; use ESP32S3.Log;
with ESP32S3.GPIO;

with Interfaces.C;

with App_State;
with Bitmap_Text;
with Card;
with Card_Books;
with Card_Library;
with Card_Reader;
with Device_Store;
with Font_Catalog;
with Font_Loader;
with Gauge;
with Int_Flash;
with Library_View;
with Mono_Frame;
with Reader_View;
with Shelf;
with Status_Bar;
with Store_Record;
with Truetype;
with X4_Display;
with X4_Touch;

pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package FS renames Card.FS;
   package Scan renames Card_Library;
   use type FS.Mount_Status;
   use type Scan.Scan_Status;
   use type Card_Books.Status;

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

   type Mode is (Library, Reading, Menu);
   Current : Mode := Library;

   --  The open book, and whether its position has changed since it was
   --  last saved (then Turned is the time of the last page turn).
   Open_Index : Natural := 0;
   Unsaved    : Boolean := False;
   Turned     : Time := Time_First;

   --  Save this long after the last page turn, to spare the flash.
   Save_Delay : constant Time_Span := Seconds (4);

   function Ms_Since (T : Time) return Integer is
     (Integer (To_Duration (Clock - T) * 1000.0));

   package Fonts is new Font_Loader (FS, Scan.Fonts_Folder);

   function Heap_Free return Interfaces.C.size_t
     with Import, Convention => C, External_Name => "__bare_heap_free_bytes";

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

   procedure Render_Library is
      T0 : constant Time := Clock;
   begin
      Library_View.Draw (Screen, Font, Books, Selected, Gauge.Read);
      Put ("[sxos] library drawn in ");
      Put (Ms_Since (T0));
      Put_Line (" ms");
      X4_Display.Show (Screen);
   end Render_Library;

   procedure Render_Reader
     (Kind : X4_Display.Refresh_Kind := X4_Display.Fast_Update)
   is
      T0 : constant Time := Clock;
   begin
      Card_Reader.Draw
        (Screen, Shelf.Title (Books, Open_Index), Gauge.Read,
         Menu => Current = Menu);
      Put ("[reader] chapter");
      Put (Card_Reader.Chapter);
      Put (" page");
      Put (Card_Reader.Page);
      Put ("/");
      Put (Card_Reader.Page_Count);
      Put (" drawn in ");
      Put (Ms_Since (T0));
      Put_Line (" ms");
      X4_Display.Show (Screen, Kind);
   end Render_Reader;

   procedure Set_Selection (I : Natural) is
   begin
      if I in 1 .. Books.Count and then I /= Selected then
         Selected := I;
         Put_Line ("[sxos] selected: " & Shelf.Name (Books, Selected));
         Render_Library;
      end if;
   end Set_Selection;

   function Book_Key (I : Shelf.Index) return Store_Record.Key is
     (Store_Record.Book_Key (Shelf.Name (Books, I), Books.Books (I).Size));

   procedure Save_Position is
      T0  : constant Time := Clock;
      Pos : constant Card_Reader.Position := Card_Reader.Where;
      Ok  : Boolean;
   begin
      Device_Store.Put
        (Book_Key (Open_Index),
         (Unsigned_32 (Pos.Chapter), Unsigned_32 (Pos.Offset), 0, 0), Ok);
      Unsaved := False;
      Put ("[store] position chapter");
      Put (Pos.Chapter);
      Put (" offset");
      Put (Pos.Offset);
      Put (if Ok then " saved in " else " NOT saved, ");
      Put (Ms_Since (T0));
      Put (" ms; generation");
      Put (Integer (Device_Store.Generation));
      Put (", slots");
      Put (Device_Store.Used_Slots);
      Put_Line ("");
   end Save_Position;

   procedure Open_Book (I : Shelf.Index) is
      T0     : constant Time := Clock;
      Result : Card_Books.Status;
      Saved  : Store_Record.Payload;
      Found  : Boolean;
      At_Pos : Card_Reader.Position;
   begin
      Device_Store.Lookup (Book_Key (I), Saved, Found);
      if Found and then Saved (1) <= Unsigned_32 (Natural'Last)
        and then Saved (2) in 1 .. Unsigned_32 (Positive'Last)
      then
         At_Pos := (Chapter => Natural (Saved (1)),
                    Offset  => Positive (Saved (2)));
      end if;
      Card_Reader.Open
        (Volume, Shelf.Name (Books, I), Font, Reader_View.Default_Size,
         At_Pos, Result);
      Put ("[reader] open " & Shelf.Name (Books, I) & ": " & Result'Image
           & ",");
      Put (Card_Reader.Chapter_Count);
      Put (" chapters, at chapter");
      Put (Card_Reader.Chapter);
      Put (" page");
      Put (Card_Reader.Page);
      Put ("/");
      Put (Card_Reader.Page_Count);
      Put (" in ");
      Put (Ms_Since (T0));
      Put (" ms, heap free ");
      Put (Integer (Heap_Free) / 1024);
      Put_Line (" KB");
      if Result /= Card_Books.OK then
         --  Stay in the Library; the next input redraws it.
         Reader_View.Draw_Message
           (Screen, Font, Shelf.Title (Books, I), Gauge.Read,
            "Cannot open: " & Result'Image);
         X4_Display.Show (Screen);
         return;
      end if;
      Open_Index := I;
      Unsaved := False;
      Current := Reading;
      Render_Reader (X4_Display.Clean);
   end Open_Book;

   procedure Close_Book is
   begin
      Save_Position;
      Card_Reader.Close;
      Current := Library;
      Render_Library;
   end Close_Book;

   procedure Turn (Step : Integer) is
      T0    : constant Time := Clock;
      Moved : Boolean;
   begin
      if Step > 0 then
         Card_Reader.Next_Page (Volume, Moved);
      else
         Card_Reader.Prev_Page (Volume, Moved);
      end if;
      Put ("[reader] turn in ");
      Put (Ms_Since (T0));
      Put_Line (if Moved then " ms" else " ms: end of the book");
      if Moved then
         Render_Reader;
         Unsaved := True;
         Turned := Clock;
      end if;
   end Turn;

   procedure On_Button (Step : Integer) is
   begin
      case Current is
         when Library =>
            Set_Selection (Selected + Step);
         when Reading =>
            Turn (Step);
         when Menu =>
            Current := Reading;
            Render_Reader;
      end case;
   end On_Button;

   procedure On_Tap (X, Y : Natural) is
      Hit : Natural;
   begin
      case Current is
         when Library =>
            Hit := Library_View.Book_At (Font, Books, Selected, Y);
            if Hit /= 0 and then Hit = Selected then
               Open_Book (Hit);
            else
               Set_Selection (Hit);
            end if;
         when Reading =>
            case Reader_View.Zone_At (X, Y) is
               when Reader_View.Menu =>
                  Current := Menu;
                  Render_Reader;
               when Reader_View.Back =>
                  Turn (-1);
               when Reader_View.Forward =>
                  Turn (1);
            end case;
         when Menu =>
            case Reader_View.Menu_At (X, Y) is
               when Reader_View.Library =>
                  Close_Book;
               when Reader_View.Close =>
                  Current := Reading;
                  Render_Reader;
            end case;
      end case;
   end On_Tap;

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
               On_Button (Step);
            end if;
         end if;
      end if;
   end Scan_Button;

   Status      : FS.Mount_Status;
   Scan_Result : Scan.Scan_Status;
   Card_Ok     : Boolean;
   Store_Ok    : Boolean;
   T_Store     : Time;

begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[sxos] bare-metal Ada Xteink X4 Pro reader");
   --  Display, SD card and touch all share the board peripheral rail, which
   --  X4_Display.Initialize raises.  The gauge shares the touch I2C bus.
   X4_Display.Initialize;
   X4_Touch.Initialize (Touch_OK);
   Gauge.Initialize;

   Put ("[store] ROM flash size ");
   Put (Integer (Int_Flash.Rom_Chip_Size / 1024));
   Put_Line (" KB");
   T_Store := Clock;
   Device_Store.Mount (Store_Ok);
   Put ("[store] mount: " & (if Store_Ok then "OK" else "FAILED") & ",");
   Put (Device_Store.Entries);
   Put (" entries, generation");
   Put (Integer (Device_Store.Generation));
   Put (", slots");
   Put (Device_Store.Used_Slots);
   Put (", in ");
   Put (Ms_Since (T_Store));
   Put_Line (" ms");

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

   Render_Library;
   Put_Line ("[sxos] library shown; awaiting input");

   loop
      delay until Clock + Milliseconds (20);
      Scan_Button (Left, Left_Pin, -1);
      Scan_Button (Right, Right_Pin, 1);

      if Unsaved and then Current /= Library and then Clock - Turned > Save_Delay
      then
         Save_Position;
      end if;

      declare
         TX, TY  : Natural;
         Contact : Boolean;
      begin
         X4_Touch.Read_Contact (TX, TY, Contact);
         if Contact then
            On_Tap (TX, TY);
         end if;
      end;
   end loop;
end Main;
