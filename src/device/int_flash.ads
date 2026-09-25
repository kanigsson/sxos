with Interfaces; use Interfaces;

with Bytes;

--  The ESP32-S3's internal SPI flash -- the chip the firmware runs from --
--  read, programmed and erased through the mask-ROM driver.
--
--  The flash cannot be read through the cache while it is being written,
--  and the cache also serves PSRAM, so each operation runs in a window
--  where nothing may touch flash or PSRAM: core 1 is stalled in hardware
--  (it idles in the runtime's scheduler, whose code and interrupt handlers
--  live in flash), interrupts are masked on core 0, both caches are
--  suspended, and only the IRAM routine in the body and the ROM run.  Data
--  goes through a small bounce buffer in internal RAM, so callers may pass
--  buffers anywhere, PSRAM included.
--
--  Addresses and lengths must be multiples of 4.  Only the region below
--  Limit is accepted, and never the running image below App_End.
package Int_Flash is

   Sector_Size : constant := 4096;

   --  The bootloader, partition table and the 1 MB factory app slot.
   App_End : constant := 16#11_0000#;
   --  The ROM driver's idea of the chip size defaults to 2 MB (the bare
   --  bootloader does not set it), and it refuses anything beyond.
   Limit   : constant := 16#20_0000#;

   procedure Read
     (Addr : Unsigned_32; Data : out Bytes.Byte_Array; Ok : out Boolean);

   procedure Program
     (Addr : Unsigned_32; Data : Bytes.Byte_Array; Ok : out Boolean);

   --  Erase the sector at Addr.
   procedure Erase (Addr : Unsigned_32; Ok : out Boolean);

   --  The chip size in the ROM driver's descriptor, for the log.
   function Rom_Chip_Size return Unsigned_32;

end Int_Flash;
