package body Reading_Settings
  with SPARK_Mode => On
is

   function Face_Hash (L : Font_Catalog.List; I : Font_Catalog.Index)
     return Unsigned_32
   is
      H : Unsigned_32 := 2166136261;
      C : Character;
   begin
      for K in 1 .. L.Faces (I).Last loop
         C := L.Faces (I).Name (K);
         if C in 'A' .. 'Z' then
            C := Character'Val (Character'Pos (C) + 32);
         end if;
         H := (H xor Unsigned_32 (Character'Pos (C))) * 16777619;
      end loop;
      return (if H = 0 then 1 else H);
   end Face_Hash;

   function Find_Face (L : Font_Catalog.List; H : Unsigned_32)
     return Font_Catalog.Count_Type is
   begin
      for I in 1 .. L.Count loop
         if Face_Hash (L, I) = H then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Face;

   function To_Payload (V : Values) return Store_Record.Payload is
     (Unsigned_32 (V.Size), V.Face, 0, 0);

   function From_Payload (P : Store_Record.Payload) return Values is
     (if P (1) in Min_Size .. Max_Size
      then (Size => Size_Type (P (1)), Face => P (2))
      else (Size => Default_Size, Face => P (2)));

end Reading_Settings;
