with Interfaces; use Interfaces;

with Bytes;

--  The records Store_Log keeps in internal flash: 32 bytes each, checked by
--  a CRC-32, so a record torn by a power cut reads as invalid rather than
--  as wrong data.
--
--    0       marker: Record_Mark, or Header_Mark for a block header;
--            16#FF# (erased flash) is a free slot
--    1       kind
--    2 .. 3  zero
--    4 .. 11 key: two 32-bit words, little-endian
--    12 .. 27  payload: four 32-bit words, little-endian
--    28 .. 31  CRC-32 of bytes 0 .. 27
package Store_Record
  with SPARK_Mode => On
is
   Size : constant := 32;

   subtype Image is Bytes.Byte_Array (0 .. Size - 1);

   type Kind is (Header, Position, Settings);

   type Key is record
      Kind : Store_Record.Kind := Position;
      A, B : Unsigned_32 := 0;
   end record;

   type Payload is array (1 .. 4) of Unsigned_32;

   --  A book: its file name's FNV-1a hash and its size, so a book with the
   --  same name but different contents starts afresh.
   function Book_Key (Name : String; File_Size : Unsigned_32) return Key;

   --  The one settings record.
   Settings_Key : constant Key := (Kind => Settings, A => 0, B => 0);

   --  Positions: (chapter, offset of the page start, 0, 0).

   procedure Encode (K : Key; P : Payload; R : out Image);

   --  Valid is False for a free slot, a torn or corrupt record, or an
   --  unknown kind.
   procedure Decode (R : Image; K : out Key; P : out Payload;
                     Valid : out Boolean);

   function Is_Free (R : Image) return Boolean is
     (for all B of R => B = 16#FF#);

end Store_Record;
