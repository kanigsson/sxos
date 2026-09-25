with Ada.Streams.Stream_IO; use Ada.Streams;

package body Image_Blocks is
   F : Stream_IO.File_Type;

   procedure Open (Path : String) is
   begin
      Stream_IO.Open (F, Stream_IO.In_File, Path);
   end Open;

   procedure Read_Blocks
     (LBA : Interfaces.Unsigned_32; Data : out Bytes.Byte_Array; Ok : out Boolean)
   is
      Raw  : Stream_Element_Array (1 .. Stream_Element_Offset (Data'Length));
      Last : Stream_Element_Offset;
   begin
      Stream_IO.Set_Index (F, Stream_IO.Positive_Count (Natural (LBA) * 512 + 1));
      Stream_IO.Read (F, Raw, Last);
      Ok := Last = Raw'Last;
      for K in Data'Range loop
         Data (K) := Bytes.Byte (Raw (Stream_Element_Offset (K - Data'First + 1)));
      end loop;
   end Read_Blocks;
end Image_Blocks;
