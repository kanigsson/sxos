--  Render one sxos screen from a host directory standing in for the SD card.
--
--    preview_main CARD library OUT.pgm [SELECTED [BATTERY%]]
--    preview_main CARD.img reader OUT.pgm BOOK [CHAPTER [PAGE [SIZE [menu]]]]
--    preview_main CARD.img contents OUT.pgm BOOK [CHAPTER [PAGE [SIZE [SELECTED]]]]
--    preview_main CARD.img settings OUT.pgm [SIZE]
--    preview_main CARD sleep|off OUT.pgm [TITLE]
--
--  With a card image, the environment variable PREVIEW_FACE names the
--  reading face (a file in /Fonts); the default face is the interface face.
--  A fallback face is chosen as on the device (Font_Loader.Choose_Fallback);
--  a CARD directory has none.
--  PREVIEW_GREY=1 draws the reader's text in grey (anti-aliased), shown in
--  the PGM as four even levels: how grey the panel makes the two grey
--  levels is up to its waveform (see X4_Display.Show_Grey).
--
--  The reader screen opens BOOK (a file name in /Books) at CHAPTER (default:
--  the first with text) and turns PAGE - 1 pages forward, at SIZE px.
--  The contents screen shows BOOK's table of contents as seen from there,
--  with entry SELECTED selected (default: the one being read).
--
--  CARD is a directory (CARD/Books, CARD/Fonts) or, if it ends in ".img", a
--  FAT32 disk image read through the same Fat32/Card_Scan/Font_Loader code
--  the firmware runs.
--  The PGM is portrait 480 x 800, as the device is held.
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Environment_Variables;
with Ada.Streams.Stream_IO;
with Ada.Text_IO; use Ada.Text_IO;

with Ada.Calendar;

with Bytes;
with Fallback;

with Image_Books;
with Image_Reader;
with Library_View;
with Reader_View;
with Reading_Settings;
with Settings_View;
with Sleep_View;
with Mono_Frame;
with Shelf;
with Status_Bar;
with Toc_View;
with Truetype;
with Host_Card;
with Font_Catalog;
with Font_Loader;
with Image_Blocks;
with Image_FS;
with Image_Scan;

procedure Preview_Main is
   Screen : Mono_Frame.Frame;
   Masks  : Mono_Frame.Grey_Masks;
   Books  : Shelf.List;
   Font   : Truetype.Font;       --  the interface face
   Read   : Truetype.Font;       --  the reading face
   Faces  : Font_Catalog.List;
   Read_Face : Font_Catalog.Count_Type := 0;
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
              (if not Mono_Frame.Is_Black (Screen, X, Y) then 255
               elsif not Mono_Frame.Is_Black (Masks.Grey, X, Y) then 0
               elsif Mono_Frame.Is_Black (Masks.Dark, X, Y) then 85
               else 170);
         end loop;
         Stream_IO.Write (F, Row);
      end loop;
      Stream_IO.Close (F);
   end Write_PGM;

begin
   Mono_Frame.Clear (Masks);
   if Argument_Count < 3 then
      Put_Line ("usage: preview_main CARD_DIR library OUT.pgm "
                & "[SELECTED [BATTERY%]]");
      Put_Line ("       preview_main CARD.img reader OUT.pgm BOOK "
                & "[CHAPTER [PAGE [SIZE [menu]]]]");
      Put_Line ("       preview_main CARD.img settings OUT.pgm [SIZE]");
      Put_Line ("       preview_main CARD sleep|off OUT.pgm [TITLE]");
      Set_Exit_Status (Failure);
      return;
   end if;

   if Is_Image then
      declare
         use type Image_FS.Mount_Status;
         package Fonts is new Font_Loader (Image_FS, Image_Scan.Fonts_Folder);
         Status : Image_FS.Mount_Status;
         Scan   : Image_Scan.Scan_Status;
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
            Read := Font;
            Read_Face := Font_Catalog.Default (Faces);
         end if;
         if Ok and then Ada.Environment_Variables.Exists ("PREVIEW_FACE") then
            Read_Face := Font_Catalog.Find
              (Faces, Ada.Environment_Variables.Value ("PREVIEW_FACE"));
            if Read_Face = 0 then
               Put_Line ("no face " & Ada.Environment_Variables.Value
                                        ("PREVIEW_FACE") & " in /Fonts");
               Set_Exit_Status (Failure);
               return;
            end if;
            Fonts.Load (Volume, Faces, Read_Face, Read, Ok);
            Put_Line ("reading face: " & Font_Catalog.File_Name (Faces, Read_Face));
         end if;
         if Ok then
            declare
               Fb_Font : Truetype.Font;
               Fb_Data : Bytes.Byte_Array_Access;
               Fb_Face : Font_Catalog.Count_Type := 0;
            begin
               Fonts.Choose_Fallback
                 (Volume, Faces, Fallback.Probe, Font, Read, Read_Face,
                  Fb_Font, Fb_Data, Fb_Face);
               if Fb_Face /= 0 then
                  Put_Line ("fallback face: "
                            & Font_Catalog.File_Name (Faces, Fb_Face));
               end if;
            end;
         end if;
      end;
   else
      Data := Host_Card.Load_Font (Argument (1));
      Ok := Data /= null;
      if Ok then
         Truetype.Open (Data, Font, Ok);
         Read := Font;
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
   elsif (Argument (2) = "reader" or else Argument (2) = "contents")
     and then Is_Image and then Argument_Count >= 4
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
           (Volume, Argument (4), Read, Arg (7, Reading_Settings.Default_Size),
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
         if Argument (2) = "contents" then
            if not Image_Reader.Has_Contents then
               Put_Line ("no contents");
               Set_Exit_Status (Failure);
               return;
            end if;
            Image_Reader.Load_Contents (Volume);
            declare
               Here : constant Natural := Image_Reader.Contents_Here;
            begin
               Toc_View.Draw
                 (Screen, Font, Argument (4),
                  Image_Reader.Contents_Labels.all,
                  Image_Reader.Contents_Lines
                    (1 .. Image_Reader.Contents_Count),
                  Arg (8, Here), Here, Batt);
               Put_Line ("contents:" & Image_Reader.Contents_Count'Image
                         & " entries, here" & Here'Image & ", drawn in"
                         & Duration'Image (Clock - T0) & " s");
            end;
            Write_PGM (Argument (3));
            return;
         end if;
         Image_Reader.Draw
           (Screen, Masks,
            Ada.Environment_Variables.Value ("PREVIEW_GREY", "") = "1",
            Font, Argument (4), Batt,
            Menu => Argument_Count >= 8 and then Argument (8) = "menu");
         Put_Line ("chapter" & Image_Reader.Chapter'Image & " of"
                   & Image_Reader.Chapter_Count'Image & ", page"
                   & Image_Reader.Page'Image & " of"
                   & Image_Reader.Page_Count'Image & ", drawn in"
                   & Duration'Image (Clock - T0) & " s, language """
                   & Image_Reader.Language & """");
      end;
   elsif Argument (2) = "settings" and then Is_Image then
      Settings_View.Draw
        (Screen, Font, Read, Font_Catalog.Display_Name (Faces, Read_Face),
         (if Argument_Count >= 4 then Positive'Value (Argument (4))
          else Reading_Settings.Default_Size),
         Ada.Environment_Variables.Value ("PREVIEW_GREY", "") = "1",
         Batt);
   elsif Argument (2) = "sleep" or else Argument (2) = "off" then
      Sleep_View.Draw
        (Screen, Font,
         (if Argument_Count >= 4 then Argument (4) else Library_View.Title),
         Batt, Off => Argument (2) = "off");
   else
      Put_Line ("unknown screen " & Argument (2));
      Set_Exit_Status (Failure);
      return;
   end if;

   Write_PGM (Argument (3));
end Preview_Main;
