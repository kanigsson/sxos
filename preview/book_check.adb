--  Exercise Book_Source over a FAT32 disk image:
--
--    book_check IMAGE              open every book in /Books, load every
--                                  chapter, report sizes, status and time
--    book_check IMAGE NAME OUT     write NAME's text to OUT, one
--                                  "=== chapter N ===" line per chapter
--    book_check IMAGE --layout [SIZE [nohyph]]
--                                  also paginate every chapter for the
--                                  Reader at SIZE px, hyphenated in the
--                                  chapter's language (Language_Guess, else
--                                  the book's metadata) unless nohyph, and
--                                  report the time
with Ada.Calendar; use Ada.Calendar;
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;

with Book_Source;
with Font_Catalog;
with Font_Loader;
with Language_Guess;
with Image_Blocks;
with Image_FS;
with Image_Hyphens;
with Image_Scan;
with Page_Layout;
with Reader_View;
with Reading_Settings;
with Shelf;
with Text_Metrics;
with Truetype;

procedure Book_Check is
   package Books is new Book_Source (Image_FS, Image_Scan.Books_Folder);
   use type Image_FS.Mount_Status;
   use type Books.Status;

   V      : Image_FS.Volume;
   Status : Image_FS.Mount_Status;
   B      : Books.Book;

   Layout  : Boolean := False;
   Hyphen  : Boolean := True;
   Font    : Truetype.Font;
   Metrics : Text_Metrics.Table;
   Geo     : Page_Layout.Geometry;
   Starts  : Page_Layout.Offset_Array (1 .. 16_384);
   type Workspace_Access is access Page_Layout.Workspace;
   Work    : constant Workspace_Access := new Page_Layout.Workspace;

   procedure Check (Name : String) is
      T0      : constant Time := Clock;
      Result  : Books.Status;
      Total   : Natural := 0;
      Largest : Natural := 0;
      Empty   : Natural := 0;
      Failed  : Natural := 0;
      Pages   : Natural := 0;
      Most    : Natural := 0;
      Slowest : Duration := 0.0;
      Lay_T   : Duration := 0.0;
   begin
      Books.Open (V, Name, B, Result);
      if Result /= Books.OK then
         Put_Line (Name & ": open " & Result'Image);
         return;
      end if;
      for I in 1 .. Books.Chapter_Count (B) loop
         Books.Load (V, B, I, Result);
         if Result /= Books.OK then
            Failed := Failed + 1;
            Put_Line ("  chapter" & I'Image & ": " & Result'Image);
         else
            Total := Total + Books.Text_Last (B);
            Largest := Natural'Max (Largest, Books.Text_Last (B));
            if Books.Text_Last (B) = 0 then
               Empty := Empty + 1;
            elsif Layout then
               declare
                  T1       : constant Time := Clock;
                  Count    : Natural;
                  Complete : Boolean;
                  G        : constant Language_Guess.Language :=
                    Language_Guess.Guess
                      (Books.Text (B) (1 .. Books.Text_Last (B)));
                  use type Language_Guess.Language;
               begin
                  if Hyphen then
                     Image_Hyphens.Select_Language
                       (V, (if G = Language_Guess.Unknown
                            then Books.Language (B)
                            else Language_Guess.Code (G)), Geo.Hyph);
                  end if;
                  Page_Layout.Paginate
                    (Metrics, Font, Geo,
                     Books.Text (B) (1 .. Books.Text_Last (B)),
                     Work.all, Starts, Count, Complete);
                  Lay_T := Lay_T + (Clock - T1);
                  Slowest := Duration'Max (Slowest, Clock - T1);
                  Pages := Pages + Count;
                  Most := Natural'Max (Most, Count);
                  if not Complete then
                     Put_Line ("  chapter" & I'Image & ": page table full");
                  end if;
               end;
            end if;
         end if;
      end loop;
      Put_Line (Name & ":" & Books.Chapter_Count (B)'Image & " chapters,"
                & Empty'Image & " empty," & Failed'Image & " failed,"
                & Total'Image & " bytes of text (largest" & Largest'Image
                & ")," & Duration'Image (Clock - T0) & " s");
      if Layout then
         Put_Line ("  layout:" & Pages'Image & " pages (most" & Most'Image
                   & " in a chapter)," & Duration'Image (Lay_T)
                   & " s, slowest chapter" & Duration'Image (Slowest) & " s");
      end if;
   end Check;

   procedure Dump (Name, Out_Path : String) is
      Result : Books.Status;
      F      : File_Type;
   begin
      Books.Open (V, Name, B, Result);
      if Result /= Books.OK then
         Put_Line ("open: " & Result'Image);
         Set_Exit_Status (Failure);
         return;
      end if;
      Create (F, Out_File, Out_Path);
      for I in 1 .. Books.Chapter_Count (B) loop
         Books.Load (V, B, I, Result);
         Put_Line (F, "=== chapter" & I'Image & " ===");
         if Result = Books.OK then
            Put_Line (F, Books.Text (B) (1 .. Books.Text_Last (B)));
         else
            Put_Line (F, "(" & Result'Image & ")");
         end if;
      end loop;
      Close (F);
   end Dump;

   L    : Shelf.List;
   Scan : Image_Scan.Scan_Status;
begin
   Image_Blocks.Open (Argument (1));
   Image_FS.Mount (V, Status);
   if Status /= Image_FS.OK then
      Put_Line ("mount: " & Status'Image);
      Set_Exit_Status (Failure);
      return;
   end if;
   if Argument_Count >= 2 and then Argument (2) = "--layout" then
      declare
         package Fonts is new Font_Loader (Image_FS, Image_Scan.Fonts_Folder);
         Faces : Font_Catalog.List;
         Ok    : Boolean;
         Size  : constant Positive :=
           (if Argument_Count >= 3 then Positive'Value (Argument (3))
            else Reading_Settings.Default_Size);
      begin
         Image_Scan.Scan_Fonts (V, Faces, Scan);
         Ok := Font_Catalog.Default (Faces) /= 0;
         if Ok then
            Fonts.Load (V, Faces, Font_Catalog.Default (Faces), Font, Ok);
         end if;
         if not Ok then
            Put_Line ("no usable font");
            Set_Exit_Status (Failure);
            return;
         end if;
         Text_Metrics.Prepare (Metrics, Font, Size);
         Geo := Page_Layout.Make
           (Metrics, Font, Reader_View.Col_Width, Reader_View.Area_Height);
         Layout := True;
         Hyphen := not (Argument_Count >= 4 and then Argument (4) = "nohyph");
      end;
   elsif Argument_Count >= 3 then
      Dump (Argument (2), Argument (3));
      return;
   end if;
   Image_Scan.Scan_Books (V, L, Scan);
   for I in 1 .. L.Count loop
      Check (Shelf.Name (L, I));
   end loop;
end Book_Check;
