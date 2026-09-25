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
     with Pre  => P in Str'Range and then Str'Last < Positive'Last,
          Post => P in P'Old + 1 .. Str'Last + 1 and then P - P'Old <= 4;

   --  Bytes Append needs for Code (1 .. 4; a surrogate or out-of-range
   --  value is encoded as Replacement).
   function Encoded_Length (Code : Code_Point) return Positive is
     (if Code < 16#80# then 1
      elsif Code < 16#800# then 2
      elsif Code in 16#D800# .. 16#DFFF# or else Code > 16#10_FFFF# then 3
      elsif Code < 16#1_0000# then 3
      else 4);

   --  Append Code's UTF-8 encoding at Buf (Last + 1 ..) and advance Last.
   --  If it does not fit, nothing is written and Last is unchanged.
   procedure Append
     (Buf  : in out String;
      Last : in out Natural;
      Code : Code_Point)
     with Pre  => Last in Buf'First - 1 .. Buf'Last,
          Post => Last in Last'Old .. Buf'Last and then Last - Last'Old <= 4;

end UTF8;
