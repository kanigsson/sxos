--  Exercise Fat32 over a disk image:
--
--    fat_check IMAGE                 list the root, Books/ and Fonts/
--    fat_check IMAGE PATH OUT        read PATH whole into OUT, then re-read it
--                                    in odd-sized chunks and compare
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Streams.Stream_IO;
with Ada.Text_IO; use Ada.Text_IO;
with Interfaces; use Interfaces;

with Bytes;
with Fat32;
with Image_Blocks;

procedure Fat_Check is
   package FS is new Fat32 (Image_Blocks.Read_Blocks);
   use type FS.Mount_Status;

   V      : FS.Volume;
   Status : FS.Mount_Status;

   procedure Show (Name : String; F : FS.File; Stop : out Boolean) is
   begin
      Put_Line ((if FS.Is_Directory (F) then "  [dir] " else "  ")
                & Name & (if FS.Is_Directory (F) then ""
                          else "  " & Unsigned_32'Image (FS.Size (F))));
      Stop := False;
   end Show;
   procedure List is new FS.Iterate (Show);

   procedure List_Path (Path : String) is
      D  : FS.File;
      Ok : Boolean;
   begin
      FS.Open (V, Path, D, Ok);
      Put_Line ("/" & Path & (if Ok then "" else "  (not found)"));
      if Ok then
         List (V, D, Ok);
         if not Ok then
            Put_Line ("  ** iterate failed");
         end if;
      end if;
   end List_Path;

begin
   Image_Blocks.Open (Argument (1));
   FS.Mount (V, Status);
   Put_Line ("mount: " & Status'Image);
   if Status /= FS.OK then
      Set_Exit_Status (Failure);
      return;
   end if;

   if Argument_Count = 1 then
      List_Path ("");
      List_Path ("Books");
      List_Path ("fonts");
      return;
   end if;

   declare
      F     : FS.File;
      Found : Boolean;
   begin
      FS.Open (V, Argument (2), F, Found);
      if not Found then
         Put_Line ("not found: " & Argument (2));
         Set_Exit_Status (Failure);
         return;
      end if;
      declare
         Size  : constant Natural := Natural (FS.Size (F));
         Whole : Bytes.Byte_Array (0 .. Size - 1);
         Count : Natural;
         Ok    : Boolean;
         Pos   : Natural := 0;
         Chunk : Natural := 1;
         Bad   : Boolean := False;
      begin
         FS.Read (V, F, 0, Whole, Count, Ok);
         Put_Line ("whole read: " & Count'Image & " bytes, ok=" & Ok'Image);
         --  Odd chunk sizes from 1 up past a cluster, so reads start and end
         --  mid-block and cross block and cluster boundaries.
         while Pos < Size loop
            declare
               Part : Bytes.Byte_Array (0 .. Chunk - 1);
            begin
               FS.Read (V, F, Unsigned_32 (Pos), Part, Count, Ok);
               if not Ok or else Count = 0 then
                  Bad := True;
                  exit;
               end if;
               for K in 0 .. Count - 1 loop
                  if Part (K) /= Whole (Pos + K) then
                     Bad := True;
                  end if;
               end loop;
               Pos := Pos + Count;
               Chunk := (Chunk * 7 + 333) mod 70_001 + 1;
            end;
         end loop;
         Put_Line ("chunked re-read matches: " & Boolean'Image (not Bad));

         declare
            use Ada.Streams;
            Out_F : Stream_IO.File_Type;
            Raw   : Stream_Element_Array (1 .. Stream_Element_Offset (Size));
         begin
            for K in Whole'Range loop
               Raw (Stream_Element_Offset (K + 1)) := Stream_Element (Whole (K));
            end loop;
            Stream_IO.Create (Out_F, Stream_IO.Out_File, Argument (3));
            Stream_IO.Write (Out_F, Raw);
            Stream_IO.Close (Out_F);
         end;
      end;
   end;
end Fat_Check;
