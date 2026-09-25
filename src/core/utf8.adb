package body UTF8
  with SPARK_Mode => On
is

   procedure Next_Code
     (Str  : String;
      P    : in out Positive;
      Code : out Code_Point)
   is
      --  A continuation byte is 10xxxxxx; its payload is the low 6 bits.
      function Is_Cont (I : Positive) return Boolean
      is (I <= Str'Last and then Character'Pos (Str (I)) / 64 = 2);

      function Payload (I : Positive) return Code_Point
      is (Code_Point (Character'Pos (Str (I)) mod 64))
      with Pre => I in Str'Range;

      B : constant Natural := Character'Pos (Str (P));
      N : Natural;          --  number of continuation bytes expected
      C : Code_Point;       --  accumulating scalar value
   begin
      --  Lead byte decides the length and seeds the value.  Anything malformed
      --  (a stray continuation byte, a truncated sequence, a 5/6-byte form)
      --  falls through to the one-byte Replacement path, so P always advances
      --  and no input can loop.
      if B < 16#80# then
         Code := Code_Point (B);
         P := P + 1;
         return;
      elsif B in 16#C2# .. 16#DF# then
         N := 1; C := Code_Point (B mod 32);
      elsif B in 16#E0# .. 16#EF# then
         N := 2; C := Code_Point (B mod 16);
      elsif B in 16#F0# .. 16#F4# then
         N := 3; C := Code_Point (B mod 8);
      else
         Code := Replacement;
         P := P + 1;
         return;
      end if;

      for K in 1 .. N loop
         if not Is_Cont (P + K) then
            Code := Replacement;
            P := P + 1;
            return;
         end if;
         C := C * 64 + Payload (P + K);
      end loop;

      Code := C;
      P := P + N + 1;
   end Next_Code;

end UTF8;
