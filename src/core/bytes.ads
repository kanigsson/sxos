with Interfaces;

--  The one byte-array type shared by the file system, the font and the book
--  buffers, so data read from the card needs no conversion on its way in.
package Bytes
  with SPARK_Mode => On
is
   subtype Byte is Interfaces.Unsigned_8;
   type Byte_Array is array (Natural range <>) of Byte;

   --  Buffers allocated at run time (the heap is in PSRAM on the device).
   type Byte_Array_Access is access all Byte_Array;
end Bytes;
