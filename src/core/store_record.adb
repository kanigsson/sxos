with Inflate;
with Inflate.CRC32;

package body Store_Record
  with SPARK_Mode => On
is
   Record_Mark : constant := 16#5A#;
   Header_Mark : constant := 16#A5#;

   function Kind_Code (K : Kind) return Unsigned_8 is
     (case K is
        when Header   => 0,
        when Position => 1,
        when Settings => 2);

   function Book_Key (Name : String; File_Size : Unsigned_32) return Key is
      H : Unsigned_32 := 2166136261;
   begin
      for C of Name loop
         H := (H xor Unsigned_32 (Character'Pos (C))) * 16777619;
      end loop;
      return (Kind => Position, A => H, B => File_Size);
   end Book_Key;

   function CRC (R : Image) return Unsigned_32 is
      Data : Inflate.Byte_Array (1 .. Size - 4) := (others => 0);
   begin
      for I in Data'Range loop
         Data (I) := Inflate.Byte (R (I - 1));
      end loop;
      return Unsigned_32 (Inflate.CRC32.Compute (Data));
   end CRC;

   procedure Put_Word (R : in out Image; At_Byte : Natural; W : Unsigned_32)
     with Pre => At_Byte <= Size - 4
   is
   begin
      for I in 0 .. 3 loop
         R (At_Byte + I) := Unsigned_8 (Shift_Right (W, 8 * I) and 16#FF#);
      end loop;
   end Put_Word;

   function Word (R : Image; At_Byte : Natural) return Unsigned_32 is
     (Unsigned_32 (R (At_Byte))
      or Shift_Left (Unsigned_32 (R (At_Byte + 1)), 8)
      or Shift_Left (Unsigned_32 (R (At_Byte + 2)), 16)
      or Shift_Left (Unsigned_32 (R (At_Byte + 3)), 24))
     with Pre => At_Byte <= Size - 4;

   procedure Encode (K : Key; P : Payload; R : out Image) is
   begin
      R := (others => 0);
      R (0) := (if K.Kind = Header then Header_Mark else Record_Mark);
      R (1) := Kind_Code (K.Kind);
      Put_Word (R, 4, K.A);
      Put_Word (R, 8, K.B);
      for I in P'Range loop
         Put_Word (R, 12 + 4 * (I - 1), P (I));
      end loop;
      Put_Word (R, 28, CRC (R));
   end Encode;

   procedure Decode (R : Image; K : out Key; P : out Payload;
                     Valid : out Boolean) is
   begin
      K := (others => <>);
      P := (others => 0);
      Valid := False;
      if Word (R, 28) /= CRC (R) or else R (2) /= 0 or else R (3) /= 0 then
         return;
      end if;
      if R (0) = Header_Mark and then R (1) = Kind_Code (Header) then
         K.Kind := Header;
      elsif R (0) = Record_Mark and then R (1) = Kind_Code (Position) then
         K.Kind := Position;
      elsif R (0) = Record_Mark and then R (1) = Kind_Code (Settings) then
         K.Kind := Settings;
      else
         return;
      end if;
      K.A := Word (R, 4);
      K.B := Word (R, 8);
      for I in P'Range loop
         P (I) := Word (R, 12 + 4 * (I - 1));
      end loop;
      Valid := True;
   end Decode;

end Store_Record;
