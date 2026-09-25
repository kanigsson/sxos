with Interfaces;
with Bytes;
with Fat32;

--  The X4 Pro's microSD slot: SDMMC slot 1, 1-bit (CLK 41, CMD 42, D0 40),
--  powered through the active-low GPIO5 gate.  Read-only.
package Card is

   --  Power the card and bring it up, retrying the OEM gate sequence.
   procedure Initialize (Ok : out Boolean);

   procedure Read_Blocks
     (LBA : Interfaces.Unsigned_32; Data : out Bytes.Byte_Array; Ok : out Boolean);

   package FS is new Fat32 (Read_Blocks);

end Card;
