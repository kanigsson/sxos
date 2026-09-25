with Interfaces; use Interfaces;

with Bytes;
with Store_Record;

--  Small key -> payload records (reading positions, settings) kept in NOR
--  flash, which can only be erased a sector at a time and programmed from
--  1 to 0 bits.
--
--  The region is two blocks of Block_Size.  One block is active: a header
--  record in its first slot with a generation number, then records appended
--  one per slot; the newest record for a key wins.  When the active block
--  is full, the live records are written to the other block, and that
--  block's header -- with the next generation -- is programmed LAST, so a
--  power cut part-way leaves the old block in charge.  A record torn by a
--  power cut fails its CRC and is skipped.
--
--  The live records are also kept in RAM (the table below), so lookups do
--  not touch flash.  The table holds Max_Entries; when a new key does not
--  fit, the least recently written one is forgotten (settings never are).
--
--  Instantiate at library level: the table is the package's state (~10 KB).
generic
   --  Flash address of the region; a multiple of Sector_Size.
   Base : Unsigned_32;
   with procedure Read
     (Addr : Unsigned_32; Data : out Bytes.Byte_Array; Ok : out Boolean);
   with procedure Program
     (Addr : Unsigned_32; Data : Bytes.Byte_Array; Ok : out Boolean);
   --  Erase the Sector_Size sector at Addr.
   with procedure Erase (Addr : Unsigned_32; Ok : out Boolean);
package Store_Log
  with SPARK_Mode => On
is
   Sector_Size : constant := 4096;
   Block_Size  : constant := 4 * Sector_Size;
   Region_Size : constant := 2 * Block_Size;
   Slots       : constant := Block_Size / Store_Record.Size;  --  incl. header
   Max_Entries : constant := 400;   --  < Slots - 1, so a compaction fits

   subtype Key is Store_Record.Key;
   subtype Payload is Store_Record.Payload;

   --  Read the region: pick the active block and load its records.  An
   --  empty or unreadable region is formatted.  Ok is False when flash
   --  failed; the store then still works from RAM for this session.
   procedure Mount (Ok : out Boolean);

   procedure Lookup (K : Key; P : out Payload; Found : out Boolean);

   --  Record P for K.  Nothing is written if K already has payload P.
   procedure Put (K : Key; P : Payload; Ok : out Boolean);

   --  For the log: the active block's generation, slots used in it
   --  (header included), and live entries.
   function Generation return Unsigned_32;
   function Used_Slots return Natural;
   function Entries return Natural;

end Store_Log;
