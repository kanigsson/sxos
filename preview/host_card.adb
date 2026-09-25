with Ada.Directories; use Ada.Directories;
with Ada.Streams.Stream_IO;
with Interfaces;

package body Host_Card is

   type Buf_Ptr is access all Truetype.Byte_Array;

   function Lower (S : String) return String is
      R : String := S;
   begin
      for C of R loop
         if C in 'A' .. 'Z' then
            C := Character'Val (Character'Pos (C) + 32);
         end if;
      end loop;
      return R;
   end Lower;

   function Load_Font (Root : String) return Truetype.Data_Ref is
      Dir    : constant String := Compose (Root, "Fonts");
      S      : Search_Type;
      E      : Directory_Entry_Type;
      Best   : String (1 .. 1024) := (others => ' ');
      Best_L : Natural := 0;
   begin
      if not Exists (Dir) then
         return null;
      end if;
      Start_Search (S, Dir, "", (Ordinary_File => True, others => False));
      while More_Entries (S) loop
         Get_Next_Entry (S, E);
         declare
            N : constant String := Simple_Name (E);
         begin
            if N'Length > 4
              and then Lower (N (N'Last - 3 .. N'Last)) = ".ttf"
              and then (Best_L = 0 or else N < Best (1 .. Best_L))
            then
               Best_L := N'Length;
               Best (1 .. Best_L) := N;
            end if;
         end;
      end loop;
      End_Search (S);
      if Best_L = 0 then
         return null;
      end if;

      declare
         use Ada.Streams;
         Path : constant String := Compose (Dir, Best (1 .. Best_L));
         Size : constant Natural := Natural (Ada.Directories.Size (Path));
         Buf  : constant Buf_Ptr := new Truetype.Byte_Array (0 .. Size - 1);
         Raw  : Stream_Element_Array (1 .. Stream_Element_Offset (Size));
         Last : Stream_Element_Offset;
         F    : Stream_IO.File_Type;
      begin
         Stream_IO.Open (F, Stream_IO.In_File, Path);
         Stream_IO.Read (F, Raw, Last);
         Stream_IO.Close (F);
         for K in Buf'Range loop
            Buf (K) := Interfaces.Unsigned_8 (Raw (Stream_Element_Offset (K + 1)));
         end loop;
         return Truetype.Data_Ref (Buf);
      end;
   end Load_Font;

   procedure Scan_Books (Root : String; L : out Shelf.List) is
      Dir : constant String := Compose (Root, "Books");
      S   : Search_Type;
      E   : Directory_Entry_Type;
   begin
      Shelf.Clear (L);
      if not Exists (Dir) then
         return;
      end if;
      Start_Search (S, Dir, "", (Ordinary_File => True, others => False));
      while More_Entries (S) loop
         Get_Next_Entry (S, E);
         if Shelf.Is_Book_Name (Simple_Name (E)) then
            Shelf.Add (L, Simple_Name (E), Interfaces.Unsigned_32 (Size (E)));
         end if;
      end loop;
      End_Search (S);
      Shelf.Sort (L);
   end Scan_Books;

end Host_Card;
