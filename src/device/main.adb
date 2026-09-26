--  sxos: mount the card, list /Books, load the font faces from /Fonts into
--  PSRAM, and run the screens.
--
--  Library: the nav buttons move the selection, a tap selects a book and a
--  tap on the selected one opens it.  Reader: Right or a tap on the right
--  two thirds turns forward, Left or a tap on the left third back; a tap on
--  the top band opens the menu over the page, whose Library button closes
--  the book.  Settings, opened from the Library's footer or the Reader's
--  menu: the reading face and size (the nav buttons change the size); they
--  are kept in internal flash, and a change re-lays out the open book at
--  its position.  Each book's position is saved to internal flash
--  (Device_Store) when the book is closed and a few seconds after the last
--  page turn, and a book reopens where it was left.  A press of the power
--  button, or ten minutes without input, puts the reader into deep sleep
--  with a sleep screen on the glass; the power button wakes it, back into
--  the book that was open.  Holding the power button turns the reader off;
--  holding it again turns it on, into the Library.  The first screen is a
--  full refresh, opening a book a clean one, and everything else a fast
--  (DU) update.
with Ada.Real_Time; use Ada.Real_Time;
with Interfaces; use Interfaces;
with System.BB.CPU_Primitives.Multiprocessors;
with ESP32S3.Log; use ESP32S3.Log;
with ESP32S3.GPIO;

with Interfaces.C;

with App_State;
with Bitmap_Text;
with Bytes;
with Card;
with Card_Books;
with Card_Library;
with Card_Reader;
with Device_Store;
with Font_Catalog;
with Font_Loader;
with Gauge;
with Glyph_Cache;
with Int_Flash;
with Library_View;
with Mono_Frame;
with Power;
with Reader_View;
with Reading_Settings;
with Settings_View;
with Shelf;
with Sleep_View;
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
   use type Bytes.Byte_Array_Access;

   --  The interface face (the default one, fixed) and the reading face (a
   --  setting).  Read_Data is the reading face's own buffer, or null when
   --  it is the interface face.
   UI_Font   : Truetype.Font;
   Have_Font : Boolean := False;
   UI_Face   : Font_Catalog.Count_Type := 0;
   Read_Font : Truetype.Font;
   Read_Face : Font_Catalog.Count_Type := 0;
   Read_Data : Bytes.Byte_Array_Access;
   Prefs     : Reading_Settings.Values;
   Selected : Natural := 0;
   Touch_OK : Boolean;

   type Mode is (Library, Reading, Menu, Settings);
   Current : Mode := Library;

   --  While in Settings: the screen to return to (Library or Reading), the
   --  settings on the way in, and whether the reading face was reloaded.
   Back_To     : Mode := Library;
   Before      : Reading_Settings.Values;
   Face_Loaded : Boolean := False;

   --  The open book, and whether its position has changed since it was
   --  last saved (then Turned is the time of the last page turn).
   Open_Index : Natural := 0;
   Unsaved    : Boolean := False;
   Turned     : Time := Time_First;

   --  Save this long after the last page turn, to spare the flash.
   Save_Delay : constant Time_Span := Seconds (4);

   --  With no input for this long, the reader goes to sleep.
   Idle_Limit : constant Time_Span := Seconds (10 * 60);
   Last_Input : Time := Clock;

   --  Held this long, the power button turns the reader off; released
   --  sooner, it puts it to sleep.
   Power_Off_Hold : constant Time_Span := Milliseconds (1500);

   function Ms_Since (T : Time) return Integer is
     (Integer (To_Duration (Clock - T) * 1000.0));

   package Fonts is new Font_Loader (FS, Scan.Fonts_Folder);

   function Heap_Free return Interfaces.C.size_t
     with Import, Convention => C, External_Name => "__bare_heap_free_bytes";

   procedure Log_Font (Face : Font_Catalog.Index; T0 : Time; Ok : Boolean) is
   begin
      Put ("[font] " & Font_Catalog.File_Name (Faces, Face) & ": ");
      Put (Integer (Faces.Faces (Face).Size));
      Put (" bytes in ");
      Put (Ms_Since (T0));
      Put (if Ok then " ms" else " ms, but it did not load");
      Put (", heap free ");
      Put (Integer (Heap_Free) / 1024);
      Put_Line (" KB");
   end Log_Font;

   procedure Load_UI_Font (Face : Font_Catalog.Index) is
      T0 : constant Time := Clock;
   begin
      Fonts.Load (Volume, Faces, Face, UI_Font, Have_Font);
      Log_Font (Face, T0, Have_Font);
      if Have_Font then
         UI_Face := Face;
         Read_Font := UI_Font;
         Read_Face := Face;
      end if;
   end Load_UI_Font;

   --  Make Face the reading face, loading it unless it is the interface
   --  face.  If it does not load, the reading face stays as it was.
   procedure Set_Read_Face (Face : Font_Catalog.Index; Ok : out Boolean) is
      T0       : constant Time := Clock;
      New_Font : Truetype.Font;
      New_Data : Bytes.Byte_Array_Access;
   begin
      Ok := True;
      if Face = Read_Face then
         return;
      end if;
      if Face = UI_Face then
         New_Font := UI_Font;
      else
         Fonts.Load (Volume, Faces, Face, New_Font, New_Data, Ok);
         Log_Font (Face, T0, Ok);
         if not Ok then
            return;
         end if;
      end if;
      --  A later face may be loaded at the freed buffer's address: forget
      --  the cached glyphs first.
      Glyph_Cache.Drop;
      if Read_Data /= null then
         Fonts.Free (Read_Data);
      end if;
      Read_Font := New_Font;
      Read_Data := New_Data;
      Read_Face := Face;
      Prefs.Face := Reading_Settings.Face_Hash (Faces, Face);
      Face_Loaded := True;
   end Set_Read_Face;

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
      Library_View.Draw (Screen, UI_Font, Books, Selected, Gauge.Read);
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
        (Screen, UI_Font, Shelf.Title (Books, Open_Index), Gauge.Read,
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
        (Volume, Shelf.Name (Books, I), Read_Font, Prefs.Size, At_Pos, Result);
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
      Put (" ms, language """ & Card_Reader.Language & """, heap free ");
      Put (Integer (Heap_Free) / 1024);
      Put_Line (" KB");
      if Result /= Card_Books.OK then
         --  Stay in the Library; the next input redraws it.
         Reader_View.Draw_Message
           (Screen, UI_Font, Shelf.Title (Books, I), Gauge.Read,
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

   procedure Render_Settings is
      T0 : constant Time := Clock;
   begin
      Settings_View.Draw
        (Screen, UI_Font, Read_Font,
         Font_Catalog.Display_Name (Faces, Read_Face), Prefs.Size,
         Gauge.Read);
      Put ("[settings] " & Font_Catalog.File_Name (Faces, Read_Face) & ",");
      Put (Prefs.Size);
      Put (" px, drawn in ");
      Put (Ms_Since (T0));
      Put_Line (" ms");
      X4_Display.Show (Screen);
   end Render_Settings;

   procedure Open_Settings (From : Mode) is
   begin
      Back_To := From;
      Before := Prefs;
      Face_Loaded := False;
      Current := Settings;
      Render_Settings;
   end Open_Settings;

   --  The next face in direction Step that loads.
   procedure Step_Face (Step : Integer) is
      I  : Font_Catalog.Index := Read_Face;
      Ok : Boolean;
   begin
      for K in 1 .. Faces.Count - 1 loop
         if Step > 0 then
            I := (if I >= Faces.Count then 1 else I + 1);
         else
            I := (if I <= 1 then Faces.Count else I - 1);
         end if;
         Set_Read_Face (I, Ok);
         exit when Ok;
      end loop;
   end Step_Face;

   procedure Save_Settings is
      Ok : Boolean;
   begin
      Device_Store.Put
        (Store_Record.Settings_Key, Reading_Settings.To_Payload (Prefs), Ok);
      Put ("[store] settings");
      Put (Prefs.Size);
      Put_Line (" px, " & Font_Catalog.File_Name (Faces, Read_Face)
                & (if Ok then "" else ": NOT saved"));
   end Save_Settings;

   --  Leave Settings for the screen it was opened from.  An open book is
   --  laid out again, at its position, when its face or size changed.
   procedure Close_Settings is
      use type Reading_Settings.Values;
      T0     : constant Time := Clock;
      Pos    : Card_Reader.Position;
      Result : Card_Books.Status;
   begin
      if Prefs /= Before then
         Save_Settings;
      end if;
      if Back_To /= Reading then
         Current := Library;
         Render_Library;
         return;
      end if;
      if not Face_Loaded and then Prefs.Size = Before.Size then
         Current := Reading;
         Render_Reader;
         return;
      end if;
      Pos := Card_Reader.Where;
      Card_Reader.Open
        (Volume, Shelf.Name (Books, Open_Index), Read_Font, Prefs.Size, Pos,
         Result);
      Put ("[reader] relaid out: " & Result'Image & ", chapter");
      Put (Card_Reader.Chapter);
      Put (" page");
      Put (Card_Reader.Page);
      Put ("/");
      Put (Card_Reader.Page_Count);
      Put (" in ");
      Put (Ms_Since (T0));
      Put_Line (" ms");
      if Result /= Card_Books.OK then
         Current := Library;
         Render_Library;
         return;
      end if;
      Current := Reading;
      Render_Reader (X4_Display.Clean);
   end Close_Settings;

   procedure On_Settings (A : Settings_View.Action) is
   begin
      case A is
         when Settings_View.None =>
            return;
         when Settings_View.Prev_Face =>
            Step_Face (-1);
         when Settings_View.Next_Face =>
            Step_Face (1);
         when Settings_View.Smaller =>
            Prefs.Size := Reading_Settings.Smaller (Prefs.Size);
         when Settings_View.Larger =>
            Prefs.Size := Reading_Settings.Larger (Prefs.Size);
         when Settings_View.Done =>
            Close_Settings;
            return;
      end case;
      Render_Settings;
   end On_Settings;

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

   --  Show the sleep screen, remember the open book (its position in
   --  flash, which book it was in RTC memory), and deep-sleep until the
   --  power button is pressed.  Off: the off screen, no book to resume,
   --  and only a long press turns the reader on.
   procedure Go_To_Sleep (Why : String; Off : Boolean := False) is
      use type Reading_Settings.Values;
      Book_Open : constant Boolean := Card_Reader.Is_Open;
   begin
      Put_Line ((if Off then "[power] turning off: "
                 else "[power] going to sleep: ") & Why);
      if Current = Settings and then Prefs /= Before then
         Save_Settings;
      end if;
      if Book_Open then
         Save_Position;
      end if;
      if Book_Open and then not Off then
         declare
            K : constant Store_Record.Key := Book_Key (Open_Index);
         begin
            Power.Set_Resume (K.A, K.B);
         end;
      else
         Power.Clear_Resume;
      end if;
      Sleep_View.Draw
        (Screen, UI_Font,
         (if Book_Open then Shelf.Title (Books, Open_Index)
          else Library_View.Title),
         Gauge.Read, Off);
      X4_Display.Show (Screen, X4_Display.Clean);
      X4_Display.Sleep;
      Power.Sleep (Off);
   end Go_To_Sleep;

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
         when Settings =>
            On_Settings
              (if Step > 0 then Settings_View.Larger
               else Settings_View.Smaller);
      end case;
   end On_Button;

   procedure On_Tap (X, Y : Natural) is
      Hit : Natural;
   begin
      case Current is
         when Library =>
            if Library_View.Settings_At (X, Y) then
               Open_Settings (Library);
               return;
            end if;
            if Library_View.Page_Step_At (X, Y) /= 0 then
               Set_Selection
                 (Library_View.Page_Target
                    (UI_Font, Books, Selected,
                     Library_View.Page_Step_At (X, Y)));
               return;
            end if;
            Hit := Library_View.Book_At (UI_Font, Books, Selected, Y);
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
               when Reader_View.Settings =>
                  Open_Settings (Reading);
               when Reader_View.Close =>
                  Current := Reading;
                  Render_Reader;
            end case;
         when Settings =>
            On_Settings (Settings_View.Action_At (X, Y));
      end case;
   end On_Tap;

   --  Debounced, edge-triggered button scan at a fixed poll cadence.
   type Button_State is record
      Pressed : Boolean := False;
      Ticks   : Natural := 0;
   end record;
   Left, Right, Power_Key : Button_State;

   --  The power button went down at Power_Down and has not been acted on.
   Power_Pending : Boolean := False;
   Power_Down    : Time := Time_First;

   --  Debounce one button at level Raw (True: pressed); Pressed_Now is set on
   --  the press edge.
   procedure Debounce
     (State : in out Button_State; Raw : Boolean; Pressed_Now : out Boolean)
   is
   begin
      Pressed_Now := False;
      if Raw = State.Pressed then
         State.Ticks := 0;
      else
         State.Ticks := State.Ticks + 1;
         if State.Ticks >= 3 then  --  60 ms of a stable new level
            State.Pressed := Raw;
            State.Ticks := 0;
            Pressed_Now := Raw;
         end if;
      end if;
   end Debounce;

   procedure Scan_Button
     (State : in out Button_State; Pin : ESP32S3.GPIO.Pin_Id; Step : Integer)
   is
      Raw : constant Boolean := not ESP32S3.GPIO.Read (Pin);  --  active-low
      Now : Boolean;
   begin
      Debounce (State, Raw, Now);
      if Now then
         Last_Input := Clock;
         On_Button (Step);
      end if;
   end Scan_Button;

   Status      : FS.Mount_Status;
   Scan_Result : Scan.Scan_Status;
   Card_Ok     : Boolean;
   Store_Ok    : Boolean;
   T_Store     : Time;

begin
   Power.Initialize;
   Power_Key.Pressed := Power.Button_Down;  --  still held from the wake
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
      Load_UI_Font (Font_Catalog.Default (Faces));
   end if;
   if not Have_Font then
      Show_Problem ("No usable font", "Put a TrueType .ttf into /Fonts.");
      loop
         delay until Clock + Seconds (60);
      end loop;
   end if;

   declare
      Saved : Store_Record.Payload;
      Found : Boolean;
      Face  : Font_Catalog.Count_Type;
      Ok    : Boolean;
   begin
      Device_Store.Lookup (Store_Record.Settings_Key, Saved, Found);
      if Found then
         Prefs := Reading_Settings.From_Payload (Saved);
         Face := Reading_Settings.Find_Face (Faces, Prefs.Face);
         if Face /= 0 then
            Set_Read_Face (Face, Ok);
         end if;
      end if;
      Prefs.Face := Reading_Settings.Face_Hash (Faces, Read_Face);
      Put ("[settings] " & (if Found then "saved" else "defaults") & ":");
      Put (Prefs.Size);
      Put_Line (" px, " & Font_Catalog.File_Name (Faces, Read_Face));
   end;

   Scan.Scan_Books (Volume, Books, Scan_Result);
   Put ("[card] books: " & Scan_Result'Image & ",");
   Put (Integer (Books.Count));
   Put_Line (" found");
   Selected := (if Books.Count > 0 then 1 else 0);

   ESP32S3.GPIO.Configure (Left_Pin, ESP32S3.GPIO.Input, ESP32S3.GPIO.Pull_Up);
   ESP32S3.GPIO.Configure (Right_Pin, ESP32S3.GPIO.Input, ESP32S3.GPIO.Pull_Up);

   --  After a wake from sleep, go back into the book that was open.
   declare
      use type Store_Record.Key;
      A, B  : Unsigned_32;
      Found : Boolean;
   begin
      Power.Take_Resume (A, B, Found);
      if Found then
         for I in 1 .. Books.Count loop
            if Book_Key (I) = (Store_Record.Position, A, B) then
               Selected := I;
               Open_Book (I);
               exit;
            end if;
         end loop;
      end if;
   end;
   if Current = Library then
      Render_Library;
      Put_Line ("[sxos] library shown; awaiting input");
   end if;
   Last_Input := Clock;

   loop
      delay until Clock + Milliseconds (20);
      Scan_Button (Left, Left_Pin, -1);
      Scan_Button (Right, Right_Pin, 1);
      declare
         Now : Boolean;
      begin
         Debounce (Power_Key, Power.Button_Down, Now);
         if Now then
            Last_Input := Clock;
            Power_Pending := True;
            Power_Down := Clock;
         elsif Power_Pending and then not Power_Key.Pressed then
            Go_To_Sleep ("power button");
         elsif Power_Pending and then Clock - Power_Down >= Power_Off_Hold
         then
            Go_To_Sleep ("power button held", Off => True);
         end if;
      end;
      if Clock - Last_Input > Idle_Limit then
         Go_To_Sleep ("idle");
      end if;

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
            Last_Input := Clock;
            On_Tap (TX, TY);
         end if;
      end;
   end loop;
end Main;
