with Interfaces; use Interfaces;

--  UTF-8 decoding over Ada Strings used as byte strings.
--
--  Text is carried as raw UTF-8 in String (compiled without -gnatW8, so one
--  Character is one byte and String'Length is a byte count).  Taken from the
--  T5 spikes' Glyphs.Next_Code.
package UTF8
  with SPARK_Mode => On
is
   --  A Unicode scalar value.
   type Code_Point is new Unsigned_32;

   --  What Next_Code yields for malformed input.
   Replacement : constant Code_Point := 16#FFFD#;

   --  Decode the sequence starting at Str (P) and advance P past it.
   --  Malformed input yields Replacement and advances one byte, so any byte
   --  string terminates.
   procedure Next_Code
     (Str  : String;
      P    : in out Positive;
      Code : out Code_Point)
     with Pre => P in Str'Range;

end UTF8;
