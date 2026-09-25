--  Render one sxos screen from a host directory standing in for the SD card.
--
--    preview_main CARD library OUT.pgm [SELECTED [BATTERY%]]
--    preview_main CARD.img reader OUT.pgm BOOK [CHAPTER [PAGE [SIZE [menu]]]]
--
--  The reader screen opens BOOK (a file name in /Books) at CHAPTER (default:
--  the first with text) and turns PAGE - 1 pages forward, at SIZE px.
--
--  CARD is a directory (CARD/Books, CARD/Fonts) or, if it ends in ".img", a
--  FAT32 disk image read through the same Fat32/Card_Scan/Font_Loader code
--  the firmware runs.
--  The PGM is portrait 480 x 800, as the device is held.
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Streams.Stream_IO;
with Ada.Text_IO; use Ada.Text_IO;

with Ada.Calendar;

with Image_Books;
with Image_Reader;
with Library_View;
with Reader_View;
with Mono_Frame;
with Shelf;
with Status_Bar;
with Truetype;
with Host_Card;
with Font_Catalog;
with Font_Loader;
with Image_Blocks;
with Image_FS;
with Image_Scan;

procedure Preview_Main is
   Screen : Mono_Frame.Frame;
   Books  : Shelf.List;
   Font   : Truetype.Font;
   Data   : Truetype.Data_Ref;
   Ok     : Boolean;
   Batt   : Status_Bar.Battery;
   use type Truetype.Data_Ref;
   Volume : Image_FS.Volume;

   function Is_Image return Boolean is
     (Argument (1)'Length > 4
      and then Argument (1) (Argument (1)'Last - 3 .. Argument (1)'Last) = ".img");

   procedure Write_PGM (Path : String) is
      use Ada.Streams;
      F      : Stream_IO.File_Type;
      Header : constant String :=
        "P5" & ASCII.LF & "480 800" & ASCII.LF & "255" & ASCII.LF;
      Row    : Stream_Element_Array (1 .. Mono_Frame.Width);
   begin
      Stream_IO.Create (F, Stream_IO.Out_File, Path);
      String'Write (Stream_IO.Stream (F), Header);
      for Y in 0 .. Mono_Frame.Height - 1 loop
         for X in 0 .. Mono_Frame.Width - 1 loop
            Row (Stream_Element_Offset (X + 1)) :=
              (if Mono_Frame.Is_Black (Screen, X, Y) then 0 else 255);
         end loop;
         Stream_IO.Write (F, Row);
      end loop;
      Stream_IO.Close (F);
   end Write_PGM;

begin
   if Argument_Count < 3 then
      Put_Line ("usage: preview_main CARD_DIR library OUT.pgm "
                & "[SELECTED [BATTERY%]]");
      Put_Line ("       preview_main CARD.img reader OUT.pgm BOOK "
                & "[CHAPTER [PAGE [SIZE [menu]]]]");
      Set_Exit_Status (Failure);
      return;
   end if;

   if Is_Image then
      declare
         use type Image_FS.Mount_Status;
         package Fonts is new Font_Loader (Image_FS, Image_Scan.Fonts_Folder);
         Status : Image_FS.Mount_Status;
         Scan   : Image_Scan.Scan_Status;
         Faces  : Font_Catalog.List;
      begin
         Image_Blocks.Open (Argument (1));
         Image_FS.Mount (Volume, Status);
         if Status /= Image_FS.OK then
            Put_Line ("mount: " & Status'Image);
            Set_Exit_Status (Failure);
            return;
         end if;
         Image_Scan.Scan_Fonts (Volume, Faces, Scan);
         Ok := Font_Catalog.Default (Faces) /= 0;
         if Ok then
            Fonts.Load (Volume, Faces, Font_Catalog.Default (Faces), Font, Ok);
            Put_Line ("font: " & Font_Catalog.File_Name (Faces, Font_Catalog.Default (Faces)));
         end if;
      end;
   else
      Data := Host_Card.Load_Font (Argument (1));
      Ok := Data /= null;
      if Ok then
         Truetype.Open (Data, Font, Ok);
      end if;
   end if;
   if not Ok then
      Put_Line ("no usable .ttf in the card's Fonts folder");
      Set_Exit_Status (Failure);
      return;
   end if;

   if Argument (2) = "library" and then Argument_Count >= 5 then
      Batt := (Known => True, Level => Natural'Value (Argument (5)),
               Charging => False);
   else
      Batt := (Known => True, Level => 80, Charging => False);
   end if;

   if Argument (2) = "library" then
      if Is_Image then
         declare
            Scan : Image_Scan.Scan_Status;
         begin
            Image_Scan.Scan_Books (Volume, Books, Scan);
         end;
      else
         Host_Card.Scan_Books (Argument (1), Books);
      end if;
      Library_View.Draw
        (Screen, Font, Books,
         (if Argument_Count >= 4 then Natural'Value (Argument (4))
          else (if Books.Count > 0 then 1 else 0)),
         Batt);
   elsif Argument (2) = "reader" and then Is_Image and then Argument_Count >= 4
   then
      declare
         use Ada.Calendar;
         use type Image_Books.Status;
         function Arg (I : Positive; Default : Natural) return Natural is
           (if Argument_Count >= I then Natural'Value (Argument (I))
            else Default);
         Result : Image_Books.Status;
         Moved  : Boolean := True;
         T0     : Time := Clock;
      begin
         Image_Reader.Open
           (Volume, Argument (4), Font, Arg (7, Reader_View.Default_Size),
            (Chapter => Arg (5, 0), Offset => 1), Result);
         Put_Line ("open: " & Result'Image & Duration'Image (Clock - T0)
                   & " s");
         if Result /= Image_Books.OK then
            Set_Exit_Status (Failure);
            return;
         end if;
         for I in 2 .. Arg (6, 1) loop
            Image_Reader.Next_Page (Volume, Moved);
            exit when not Moved;
         end loop;
         T0 := Clock;
         Image_Reader.Draw
           (Screen, Argument (4), Batt,
            Menu => Argument_Count >= 8 and then Argument (8) = "menu");
         Put_Line ("chapter" & Image_Reader.Chapter'Image & " of"
                   & Image_Reader.Chapter_Count'Image & ", page"
                   & Image_Reader.Page'Image & " of"
                   & Image_Reader.Page_Count'Image & ", drawn in"
                   & Duration'Image (Clock - T0) & " s");
      end;
   else
      Put_Line ("unknown screen " & Argument (2));
      Set_Exit_Status (Failure);
      return;
   end if;

   Write_PGM (Argument (3));
end Preview_Main;
