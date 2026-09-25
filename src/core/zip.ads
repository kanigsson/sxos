with Interfaces; use Interfaces;
with Bytes;

--  The parts of a ZIP file an EPUB needs: find the central directory, look
--  a member up in it by name, and locate a member's data.  Parsing only;
--  the caller reads the bytes (the tail of the file, the directory, a local
--  header) and hands them in.  No ZIP64, no encryption, no multi-disk.
package Zip
  with SPARK_Mode => On
is
   --  The end-of-central-directory record is within the last Tail_Size
   --  bytes of the file (22 bytes plus a comment of up to 64 KB).
   Tail_Size : constant := 22 + 65_535;

   type Directory is record
      Offset  : Unsigned_32 := 0;   --  of the central directory in the file
      Size    : Unsigned_32 := 0;   --  bytes
      Entries : Natural := 0;
   end record;

   --  Tail is the file's last Tail'Length bytes (all of it if shorter than
   --  Tail_Size); File_Size is the whole file's.
   procedure Find_Directory
     (Tail      : Bytes.Byte_Array;
      File_Size : Unsigned_32;
      Dir       : out Directory;
      Found     : out Boolean);

   Stored   : constant := 0;
   Deflated : constant := 8;

   type Member is record
      Method        : Natural := 0;
      CRC           : Unsigned_32 := 0;
      Compressed    : Unsigned_32 := 0;
      Size          : Unsigned_32 := 0;   --  uncompressed
      Header_Offset : Unsigned_32 := 0;   --  of its local header
   end record;

   --  Look Name up in the central directory bytes Dir.  An exact match wins;
   --  otherwise the first match ignoring ASCII letter case (EPUB hrefs and
   --  archive names sometimes disagree on case).
   procedure Find
     (Dir   : Bytes.Byte_Array;
      Name  : String;
      M     : out Member;
      Found : out Boolean);

   --  The fixed part of a local header; the data starts after it, the name
   --  and the extra field, whose lengths only the local header gives.
   Local_Header_Size : constant := 30;

   procedure Data_Offset
     (Header : Bytes.Byte_Array;
      M      : Member;
      Offset : out Unsigned_32;
      Ok     : out Boolean)
     with Pre => Header'Length = Local_Header_Size;
end Zip;
