with Interfaces;
with Bytes;

--  Block reads from a disk-image file: the host's stand-in for the SD card,
--  to run the real Fat32 code over.
package Image_Blocks is
   procedure Open (Path : String);
   procedure Read_Blocks
     (LBA : Interfaces.Unsigned_32; Data : out Bytes.Byte_Array; Ok : out Boolean);
end Image_Blocks;
