--  Walk every book in a FAT32 image through the Reader, as the page-turn
--  buttons would:
--
--    reader_check IMAGE [SIZE]
--
--  From the first page, turn forward to the end of the book and back to the
--  start, checking that both walks visit the same number of pages, that the
--  position only ever moves one way, and that reopening at a position lands
--  on the same page.  Then go to every entry of the table of contents and
--  check that the Reader counts the page it lands on as that entry's (or
--  as an entry's that starts on the same page).  PREVIEW_FACE names the face (default: the
--  catalogue's).
with Ada.Calendar; use Ada.Calendar;
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Environment_Variables;
with Ada.Text_IO; use Ada.Text_IO;

with Bytes;
with Fallback;
with Font_Catalog;
with Font_Loader;
with Image_Blocks;
with Image_Books;
with Image_FS;
with Image_Reader;
with Image_Scan;
with Reader_View;
with Reading_Settings;
with Shelf;
with Truetype;

procedure Reader_Check is
   package Fonts is new Font_Loader (Image_FS, Image_Scan.Fonts_Folder);
   use type Image_FS.Mount_Status;
   use type Image_Books.Status;
   use type Image_Reader.Position;

   V      : Image_FS.Volume;
   Status : Image_FS.Mount_Status;
   Scan   : Image_Scan.Scan_Status;
   Faces  : Font_Catalog.List;
   Face   : Font_Catalog.Count_Type;
   Font   : Truetype.Font;
   Ok     : Boolean;
   L      : Shelf.List;
   Size   : Positive := Reading_Settings.Default_Size;
   Errors : Natural := 0;

   function "<" (A, B : Image_Reader.Position) return Boolean is
     (A.Chapter < B.Chapter
      or else (A.Chapter = B.Chapter and then A.Offset < B.Offset));

   procedure Fail (Name, Msg : String) is
   begin
      Put_Line (Name & ": FAIL " & Msg);
      Errors := Errors + 1;
   end Fail;

   procedure Check (Name : String) is
      T0      : constant Time := Clock;
      Result  : Image_Books.Status;
      Moved   : Boolean;
      Forward : Natural := 1;
      Back    : Natural := 1;
      Prev    : Image_Reader.Position;
      Mid     : Image_Reader.Position;
      Mid_Page, Mid_Chapter : Natural := 0;
   begin
      Image_Reader.Open (V, Name, Font, Size, (others => <>), Result);
      if Result /= Image_Books.OK then
         Fail (Name, "open " & Result'Image);
         return;
      end if;
      Image_Reader.Prev_Page (V, Moved);
      if Moved then
         Fail (Name, "turned back from the first page");
      end if;

      Prev := Image_Reader.Where;
      loop
         Image_Reader.Next_Page (V, Moved);
         exit when not Moved;
         Forward := Forward + 1;
         if not (Prev < Image_Reader.Where) then
            Fail (Name, "forward turn did not advance");
            exit;
         end if;
         Prev := Image_Reader.Where;
         if Forward = 2 * (Forward / 2) and then Mid_Page = 0
           and then Image_Reader.Page > 1
         then
            --  Somewhere past the first page of a chapter.
            Mid := Image_Reader.Where;
            Mid_Page := Image_Reader.Page;
            Mid_Chapter := Image_Reader.Chapter;
         end if;
      end loop;
      if Image_Reader.Where /= Prev then
         Fail (Name, "the failed turn at the end moved the position");
      end if;

      loop
         Image_Reader.Prev_Page (V, Moved);
         exit when not Moved;
         Back := Back + 1;
         if not (Image_Reader.Where < Prev) then
            Fail (Name, "backward turn did not go back");
            exit;
         end if;
         Prev := Image_Reader.Where;
      end loop;
      if Forward /= Back then
         Fail (Name, "forward" & Forward'Image & " pages, back" & Back'Image);
      end if;

      if Mid_Page /= 0 then
         Image_Reader.Open (V, Name, Font, Size, Mid, Result);
         if Image_Reader.Chapter /= Mid_Chapter
           or else Image_Reader.Page /= Mid_Page
         then
            Fail (Name, "reopened at chapter" & Image_Reader.Chapter'Image
                  & " page" & Image_Reader.Page'Image & ", expected"
                  & Mid_Chapter'Image & Mid_Page'Image);
         end if;
      end if;

      if Image_Reader.Has_Contents then
         Image_Reader.Load_Contents (V);
         for I in 1 .. Image_Reader.Contents_Count loop
            Image_Reader.Go_To_Entry (V, I, Moved);
            if not Moved then
               Fail (Name, "could not go to entry" & I'Image);
            else
               declare
                  Here : constant Natural := Image_Reader.Contents_Here;
                  At_I : constant Image_Reader.Position := Image_Reader.Where;
               begin
                  if Here = 0 then
                     Fail (Name, "no entry here after going to" & I'Image);
                  elsif Here /= I then
                     Image_Reader.Go_To_Entry (V, Here, Moved);
                     if Image_Reader.Where /= At_I then
                        Fail (Name, "went to entry" & I'Image
                              & " (chapter" & At_I.Chapter'Image
                              & " offset" & At_I.Offset'Image
                              & "), but it counts as entry" & Here'Image);
                     end if;
                  end if;
               end;
            end if;
         end loop;
         Put_Line (Name & ":" & Image_Reader.Contents_Count'Image
                   & " contents entries visited");
      end if;

      Image_Reader.Close;
      Put_Line (Name & ":" & Forward'Image & " pages,"
                & Duration'Image (Clock - T0) & " s");
   end Check;

begin
   Image_Blocks.Open (Argument (1));
   if Argument_Count >= 2 then
      Size := Positive'Value (Argument (2));
   end if;
   Image_FS.Mount (V, Status);
   if Status /= Image_FS.OK then
      Put_Line ("mount: " & Status'Image);
      Set_Exit_Status (Failure);
      return;
   end if;
   Image_Scan.Scan_Fonts (V, Faces, Scan);
   Face := Font_Catalog.Default (Faces);
   if Ada.Environment_Variables.Exists ("PREVIEW_FACE") then
      Face := Font_Catalog.Find
        (Faces, Ada.Environment_Variables.Value ("PREVIEW_FACE"));
   end if;
   Ok := Face /= 0;
   if Ok then
      Fonts.Load (V, Faces, Face, Font, Ok);
   end if;
   if Ok then
      declare
         Fb_Font : Truetype.Font;
         Fb_Data : Bytes.Byte_Array_Access;
         Fb_Face : Font_Catalog.Count_Type := 0;
      begin
         Fonts.Choose_Fallback
           (V, Faces, Fallback.Probe, Font, Font, Face,
            Fb_Font, Fb_Data, Fb_Face);
      end;
   end if;
   if not Ok then
      Put_Line ("no usable font");
      Set_Exit_Status (Failure);
      return;
   end if;
   Image_Scan.Scan_Books (V, L, Scan);
   for I in 1 .. L.Count loop
      Check (Shelf.Name (L, I));
   end loop;
   Put_Line (if Errors = 0 then "all good" else Errors'Image & " failures");
   if Errors > 0 then
      Set_Exit_Status (Failure);
   end if;
end Reader_Check;
