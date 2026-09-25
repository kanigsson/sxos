package body Shelf
  with SPARK_Mode => On
is

   function Lower (C : Character) return Character is
     (if C in 'A' .. 'Z'
      then Character'Val (Character'Pos (C) + 32) else C);

   function Ends_With (Name, Suffix : String) return Boolean is
     (Name'Length >= Suffix'Length
      and then (for all K in 0 .. Suffix'Length - 1 =>
                  Lower (Name (Name'Last - Suffix'Length + 1 + K))
                  = Suffix (Suffix'First + K)));

   function Format_Of (Name : String) return Book_Format is
     (if Ends_With (Name, ".epub") then EPUB
      elsif Ends_With (Name, ".txt") then TXT
      else Unknown);

   function Is_Book_Name (Name : String) return Boolean is
     (Format_Of (Name) /= Unknown);

   procedure Clear (L : out List) is
   begin
      L := (Books => (others => (Name => (others => ' '), Last => 0, Size => 0)),
            Count => 0);
   end Clear;

   procedure Add (L : in out List; Name : String; Size : Unsigned_32) is
      N : Natural := Natural'Min (Name'Length, Max_Name);
   begin
      if L.Count = Max_Books then
         return;
      end if;
      --  Do not end inside a multi-byte sequence: back off continuation
      --  bytes (10xxxxxx) and then the lead byte they belong to.
      if N < Name'Length then
         while N > 0
           and then Character'Pos (Name (Name'First + N)) / 64 = 2
         loop
            N := N - 1;
         end loop;
      end if;
      L.Count := L.Count + 1;
      L.Books (L.Count).Name := (others => ' ');
      L.Books (L.Count).Name (1 .. N) := Name (Name'First .. Name'First + N - 1);
      L.Books (L.Count).Last := N;
      L.Books (L.Count).Size := Size;
   end Add;

   function Name (L : List; I : Index) return String is
     (L.Books (I).Name (1 .. L.Books (I).Last));

   function Title (L : List; I : Index) return String is
      B : Book renames L.Books (I);
   begin
      for K in reverse 2 .. B.Last loop
         if B.Name (K) = '.' then
            return B.Name (1 .. K - 1);
         end if;
      end loop;
      return B.Name (1 .. B.Last);
   end Title;

   function Less (A, B : Book) return Boolean is
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
      --  Insertion sort: a few hundred entries, sorted once per scan.
      for I in 2 .. L.Count loop
         declare
            Item : constant Book := L.Books (I);
            J    : Natural := I - 1;
         begin
            while J >= 1 and then Less (Item, L.Books (J)) loop
               L.Books (J + 1) := L.Books (J);
               J := J - 1;
            end loop;
            L.Books (J + 1) := Item;
         end;
      end loop;
   end Sort;

end Shelf;
