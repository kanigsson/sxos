--  Exercise Book_Source over a FAT32 disk image:
--
--    book_check IMAGE              open every book in /Books, load every
--                                  chapter, report sizes, status and time
--    book_check IMAGE NAME OUT     write NAME's text to OUT, one
--                                  "=== chapter N ===" line per chapter
with Ada.Calendar; use Ada.Calendar;
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;

with Book_Source;
with Image_Blocks;
with Image_FS;
with Image_Scan;
with Shelf;

procedure Book_Check is
   package Books is new Book_Source (Image_FS, Image_Scan.Books_Folder);
   use type Image_FS.Mount_Status;
   use type Books.Status;

   V      : Image_FS.Volume;
   Status : Image_FS.Mount_Status;
   B      : Books.Book;

   procedure Check (Name : String) is
      T0      : constant Time := Clock;
      Result  : Books.Status;
      Total   : Natural := 0;
      Largest : Natural := 0;
      Empty   : Natural := 0;
      Failed  : Natural := 0;
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
            end if;
         end if;
      end loop;
      Put_Line (Name & ":" & Books.Chapter_Count (B)'Image & " chapters,"
                & Empty'Image & " empty," & Failed'Image & " failed,"
                & Total'Image & " bytes of text (largest" & Largest'Image
                & ")," & Duration'Image (Clock - T0) & " s");
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
   if Argument_Count >= 3 then
      Dump (Argument (2), Argument (3));
      return;
   end if;
   Image_Scan.Scan_Books (V, L, Scan);
   for I in 1 .. L.Count loop
      Check (Shelf.Name (L, I));
   end loop;
end Book_Check;
