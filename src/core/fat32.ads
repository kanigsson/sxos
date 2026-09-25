with Interfaces; use Interfaces;
with Bytes;

--  Read-only FAT32: mount, walk directories (VFAT long names, as UTF-8), and
--  read files at any offset.
--
--  Everything here is parsing; the storage itself is the formal Read_Blocks,
--  so the same code runs over the SD card on the device and over a disk image
--  on the host.  Accepts an MBR partition of type 0x0B/0x0C, or a FAT32 boot
--  sector at block 0 (a "superfloppy").  No FAT12/16, exFAT or GPT.
--
--  Nothing is ever written.  Every loop over a cluster chain is bounded by the
--  volume's cluster count, so a corrupt (even cyclic) FAT terminates.
generic
   --  Read Data'Length / Block_Size consecutive blocks starting at LBA.
   --  Data'Length is always a positive multiple of Block_Size.
   with procedure Read_Blocks
     (LBA : Unsigned_32; Data : out Bytes.Byte_Array; Ok : out Boolean);
package Fat32
  with SPARK_Mode => On
is
   Block_Size : constant := 512;

   --  A long name is up to 255 UTF-16 units; as UTF-8 that is at most 765
   --  bytes (a surrogate pair is two units and four bytes).
   Max_Name : constant := 765;

   type Mount_Status is (OK, Read_Error, Unsupported_FS, Invalid_FS);

   type Volume is private;

   procedure Mount (V : out Volume; Status : out Mount_Status);

   --  A file or directory, with a cursor into its cluster chain so that
   --  sequential Reads do not re-walk the chain from the start.
   type File is private;

   function Size (F : File) return Unsigned_32;
   function Is_Directory (F : File) return Boolean;

   function Root (V : Volume) return File;

   --  Call Visit for each entry of Dir (not "." / ".."), in disk order.
   --  Name is UTF-8.  Setting Stop ends the walk early.  Ok is False on a
   --  read error or a broken chain.
   generic
      with procedure Visit (Name : String; F : File; Stop : out Boolean);
   procedure Iterate (V : in out Volume; Dir : File; Ok : out Boolean);

   --  Look up Path relative to the root, components separated by '/', with
   --  ASCII letters compared case-insensitively ("books/X.EPUB" matches
   --  "Books/x.epub").
   procedure Open
     (V     : in out Volume;
      Path  : String;
      F     : out File;
      Found : out Boolean);

   --  Read up to Into'Length bytes starting at byte Offset of F.  Count is
   --  how many were read (fewer only at end of file).  Ok is False on a read
   --  error or a chain that ends before the file does.
   procedure Read
     (V      : in out Volume;
      F      : in out File;
      Offset : Unsigned_32;
      Into   : out Bytes.Byte_Array;
      Count  : out Natural;
      Ok     : out Boolean);

private

   subtype Sector is Bytes.Byte_Array (0 .. Block_Size - 1);

   type Volume is record
      Mounted       : Boolean := False;
      Fat_Start     : Unsigned_32 := 0;   --  LBA of the first FAT
      Fat_Size      : Unsigned_32 := 0;   --  blocks per FAT
      Data_Start    : Unsigned_32 := 0;   --  LBA of cluster 2
      --  Blocks per cluster: a power of two that fits the boot sector's
      --  byte, so never 0 and a cluster is at most 64 KB.
      Per_Cluster   : Unsigned_32 range 1 .. 128 := 1;
      Clusters      : Unsigned_32 := 0;   --  data clusters (2 .. Clusters + 1)
      Root_Cluster  : Unsigned_32 := 2;
      Fat_Cache     : Sector := (others => 0);
      Fat_Cache_LBA : Unsigned_32 := Unsigned_32'Last;
      Buf           : Sector := (others => 0);   --  partial-block reads
   end record;

   type File is record
      First     : Unsigned_32 := 0;       --  first cluster; 0 = empty file
      Size      : Unsigned_32 := 0;
      Directory : Boolean := False;
      Cur_Index : Unsigned_32 := 0;       --  cursor: chain position ...
      Cur       : Unsigned_32 := 0;       --  ... and the cluster there
   end record;

   function Size (F : File) return Unsigned_32 is (F.Size);
   function Is_Directory (F : File) return Boolean is (F.Directory);

end Fat32;
