package body Font_Catalog
  with SPARK_Mode => On
is

   function Lower (C : Character) return Character is
     (if C in 'A' .. 'Z' then Character'Val (Character'Pos (C) + 32) else C);

   function Same (A, B : String) return Boolean is
     (A'Length = B'Length
      and then (for all K in 0 .. A'Length - 1 =>
                  Lower (A (A'First + K)) = Lower (B (B'First + K))));

   function Contains (S, Part : String) return Boolean is
   begin
      if Part'Length = 0 or else S'Length < Part'Length then
         return Part'Length = 0;
      end if;
      for K in S'First .. S'Last - Part'Length + 1 loop
         if Same (S (K .. K + Part'Length - 1), Part) then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   function Has_Ttf (N : String) return Boolean is
     (N'Length > 4 and then Same (N (N'Last - 3 .. N'Last), ".ttf"));

   function Is_Regular (File_Name : String) return Boolean is
      Dash : Natural := 0;
   begin
      if not Has_Ttf (File_Name) then
         return False;
      end if;
      for K in File_Name'First .. File_Name'Last - 4 loop
         pragma Loop_Invariant (Dash = 0 or else Dash in File_Name'First .. K);
         if File_Name (K) = '-' then
            Dash := K;
         end if;
      end loop;
      if Dash = 0 then
         return True;
      end if;
      declare
         Style : constant String := File_Name (Dash + 1 .. File_Name'Last - 4);
         Words : constant array (1 .. 11) of String (1 .. 7) :=
           ("bold   ", "italic ", "oblique", "light  ", "thin   ", "black  ",
            "medium ", "semi   ", "extra  ", "heavy  ", "condens");
      begin
         for W of Words loop
            declare
               L : Natural := 7;
            begin
               while L > 0 and then W (L) = ' ' loop
                  pragma Loop_Invariant (L <= 7);
                  pragma Loop_Variant (Decreases => L);
                  L := L - 1;
               end loop;
               if Contains (Style, W (1 .. L)) then
                  return False;
               end if;
            end;
         end loop;
         return True;
      end;
   end Is_Regular;

   procedure Clear (L : out List) is
   begin
      L := (Faces => (others => (Name => (others => ' '), Last => 0, Size => 0)),
            Count => 0);
   end Clear;

   procedure Consider (L : in out List; File_Name : String; Size : Unsigned_32) is
   begin
      if Is_Regular (File_Name) and then File_Name'Length <= Max_Name
        and then L.Count < Max_Faces
      then
         L.Count := L.Count + 1;
         L.Faces (L.Count).Name := (others => ' ');
         L.Faces (L.Count).Name (1 .. File_Name'Length) := File_Name;
         L.Faces (L.Count).Last := File_Name'Length;
         L.Faces (L.Count).Size := Size;
      end if;
   end Consider;

   function Less (A, B : Face) return Boolean is
   begin
      for K in 1 .. Natural'Min (A.Last, B.Last) loop
         if Lower (A.Name (K)) /= Lower (B.Name (K)) then
            return Lower (A.Name (K)) < Lower (B.Name (K));
         end if;
      end loop;
      return A.Last < B.Last;
   end Less;

   procedure Sort (L : in out List) is
   begin
      for I in 2 .. L.Count loop
         declare
            Item : constant Face := L.Faces (I);
            J    : Natural := I - 1;
         begin
            while J >= 1 and then Less (Item, L.Faces (J)) loop
               pragma Loop_Invariant (J < I);
               pragma Loop_Variant (Decreases => J);
               L.Faces (J + 1) := L.Faces (J);
               J := J - 1;
            end loop;
            L.Faces (J + 1) := Item;
         end;
      end loop;
   end Sort;

   function File_Name (L : List; I : Index) return String is
     (L.Faces (I).Name (1 .. L.Faces (I).Last));

   function Display_Name (L : List; I : Index) return String is
      N    : constant String := File_Name (L, I);
      --  Drop ".ttf" (only names that end in it are added).
      Last : Natural := (if N'Length > 4 then N'Last - 4 else N'Last);
      Reg  : constant String := "-regular";
   begin
      if Last - N'First + 1 > Reg'Length
        and then Same (N (Last - Reg'Length + 1 .. Last), Reg)
      then
         Last := Last - Reg'Length;
      end if;
      return N (N'First .. Last);
   end Display_Name;

   function Find (L : List; Name : String) return Count_Type is
   begin
      for I in 1 .. L.Count loop
         if Same (File_Name (L, I), Name) then
            return I;
         end if;
      end loop;
      return 0;
   end Find;

   function Default (L : List) return Count_Type is
     (if L.Count = 0 then 0
      elsif Find (L, Preferred_Default) /= 0 then Find (L, Preferred_Default)
      else 1);

end Font_Catalog;
