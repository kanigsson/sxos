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
--                                  report the time; check every line
--                                  against Reader_View's measure, and
--                                  report lines the next word would fit
--                                  on.  PREVIEW_FACE names the face.
with Ada.Calendar; use Ada.Calendar;
with Ada.Environment_Variables;
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
with UTF8;

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

   Short : Natural := 0;

   --  Measure every line of every page of Text as Reader_View.Draw_Line
   --  draws it, and report lines whose Width or Spaces disagree with the
   --  layout's, and lines that end short although the next word fits.
   --  The code point starting at byte P of Text.
   function Code_At (Text : String; P : Positive) return UTF8.Code_Point is
      Q : Positive := P;
      C : UTF8.Code_Point;
   begin
      UTF8.Next_Code (Text, Q, C);
      return C;
   end Code_At;

   procedure Verify (Text : String; Count : Natural; Bad : in out Natural)
   is
      use type UTF8.Code_Point;
      Space_W  : constant Natural :=
        Text_Metrics.Advance (Metrics, Font, Character'Pos (' '));
      Hyphen_W : constant Natural :=
        Text_Metrics.Advance (Metrics, Font, Character'Pos ('-'));
      N : Positive;
   begin
      for Pg in 1 .. Count loop
         Page_Layout.Page_Lines
           (Metrics, Font, Geo, Text, Starts (Pg), Work.all, N);
         for I in 1 .. N loop
            declare
               L    : constant Page_Layout.Line := Work.Lines (I);
               X    : Integer := 0;
               Sp   : Natural := 0;
               P    : Positive := L.First;
               C    : UTF8.Code_Point;
               Prev : UTF8.Code_Point := Text_Metrics.No_Code;
            begin
               while P <= L.Last loop
                  if Text (P) = ' ' then
                     X := X + Space_W;
                     Sp := Sp + 1;
                     Prev := Text_Metrics.No_Code;
                     P := P + 1;
                  else
                     UTF8.Next_Code (Text, P, C);
                     if C /= 16#AD# then
                        X := X + Text_Metrics.Kern (Metrics, Prev, C)
                          + Text_Metrics.Advance (Metrics, Font, C);
                        Prev := C;
                     end if;
                  end if;
               end loop;
               if L.Hyphen then
                  X := X + Text_Metrics.Kern (Metrics, Prev, Character'Pos ('-'))
                    + Hyphen_W;
               end if;
               --  The next word (or syllable), if the line ends at a space
               --  or between two syllables.
               if not L.Para_End and then L.Last < Text'Last
                 and then (Text (L.Last + 1) = ' '
                           or else (not L.Hyphen
                                    and then Page_Layout.Breaks_Between
                                               (Prev, Code_At (Text, L.Next))))
               then
                  declare
                     Budget : constant Integer :=
                       Geo.Col_Width - (if L.Indented then Geo.Indent else 0);
                     Y      : Integer :=
                       X + (if Text (L.Last + 1) = ' ' then Space_W else 0);
                     Q      : Positive := L.Next;
                     Q2     : Positive;
                  begin
                     Prev := Text_Metrics.No_Code;
                     while Q <= Text'Last and then Text (Q) /= ' '
                       and then Text (Q) /= ASCII.LF
                     loop
                        Q2 := Q;
                        UTF8.Next_Code (Text, Q2, C);
                        exit when Page_Layout.Breaks_Between (Prev, C);
                        Q := Q2;
                        Y := Y + Text_Metrics.Kern (Metrics, Prev, C)
                          + Text_Metrics.Advance (Metrics, Font, C);
                        Prev := C;
                     end loop;
                     if Y <= Budget then
                        Short := Short + 1;
                        if Short <= 10 then
                           Put_Line ("    short line (" & X'Image & ","
                                     & Y'Image & " of" & Budget'Image
                                     & "): [" & Text (L.First .. L.Last)
                                     & "] next [" & Text (L.Next .. Q - 1)
                                     & "]");
                        end if;
                     end if;
                  end;
               end if;
               if X /= L.Width or else Sp /= L.Spaces then
                  Bad := Bad + 1;
                  if Bad <= 10 then
                     Put_Line ("    line width" & L.Width'Image & " spaces"
                               & L.Spaces'Image & ", measured" & X'Image
                               & Sp'Image & ": [" & Text (L.First .. L.Last)
                               & "]");
                  end if;
               end if;
            end;
         end loop;
      end loop;
   end Verify;

   Mismatches : Natural := 0;

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
                  Verify (Books.Text (B) (1 .. Books.Text_Last (B)), Count,
                          Mismatches);
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
         Face  : Font_Catalog.Count_Type;
         Ok    : Boolean;
         Size  : constant Positive :=
           (if Argument_Count >= 3 then Positive'Value (Argument (3))
            else Reading_Settings.Default_Size);
      begin
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
   if Layout then
      Put_Line ("lines measured differently:" & Mismatches'Image);
      Put_Line ("short lines (the next word fits):" & Short'Image);
   end if;
end Book_Check;
