with Interfaces;

package body Fallback
  with SPARK_Mode => On,
       Refined_State => (State => (Faces, N))
is
   Faces : array (Index) of Truetype.Font;
   N     : Count_Type := 0;

   procedure Clear is
   begin
      N := 0;
   end Clear;

   procedure Add (F : Truetype.Font) is
      Same : Boolean;
   begin
      for I in 1 .. N loop
         Same := Truetype.Identity.Same_Face (Faces (I), F);
         if Same then
            return;
         end if;
      end loop;
      if N < Max_Faces then
         N := N + 1;
         Faces (N) := F;
      end if;
   end Add;

   function Count return Count_Type is (N)
     with Refined_Global => N;

   function Face (I : Index) return Truetype.Font is (Faces (I))
     with Refined_Global => (Input => Faces, Proof_In => N);

   procedure Find
     (F      : Truetype.Font;
      C      : UTF8.Code_Point;
      Found  : out Truetype.Font;
      Source : out Count_Type;
      G      : out Natural) is
   begin
      Found := F;
      Source := 0;
      G := Truetype.Glyph_Index (F, Interfaces.Unsigned_32 (C));
      --  F may be in the chain too: asking it again finds nothing again.
      for I in 1 .. N loop
         exit when G /= 0;
         G := Truetype.Glyph_Index (Faces (I), Interfaces.Unsigned_32 (C));
         if G /= 0 then
            Found := Faces (I);
            Source := I;
         end if;
      end loop;
   end Find;

end Fallback;
