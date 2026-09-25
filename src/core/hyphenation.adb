package body Hyphenation
  with SPARK_Mode => On
is
   use type UTF8.Code_Point;

   subtype Pattern_Codes is Code_Array (1 .. Max_Pattern);
   type Digit_Array is array (0 .. Max_Pattern) of Unsigned_8;

   function Is_Blank (C : Character) return Boolean is
     (C = ' ' or else C = ASCII.HT or else C = ASCII.LF or else C = ASCII.CR);

   --  Skip white space and '%' comments from P; Found is False at the end.
   procedure Skip_Blanks (Text : String; P : in out Positive; Found : out Boolean)
     with Pre  => P >= Text'First,
          Post => P >= P'Old
                  and then (if Found then P in Text'Range
                                          and then not Is_Blank (Text (P)))
   is
   begin
      Found := False;
      while P <= Text'Last loop
         pragma Loop_Invariant (P >= P'Loop_Entry);
         if Text (P) = '%' then
            while P <= Text'Last and then Text (P) /= ASCII.LF loop
               pragma Loop_Invariant (P >= P'Loop_Entry);
               exit when P = Positive'Last;
               P := P + 1;
            end loop;
         elsif Is_Blank (Text (P)) then
            null;
         else
            Found := True;
            return;
         end if;
         exit when P = Positive'Last;
         P := P + 1;
      end loop;
   end Skip_Blanks;

   --  The pattern at P: its letters (1 .. Count) and the digit before each
   --  letter and after the last (0 .. Count).  P moves past it.  Ok is False
   --  for a pattern with more than Max_Pattern letters.
   procedure Next_Pattern
     (Text  : String;
      P     : in out Positive;
      Codes : out Pattern_Codes;
      Dig   : out Digit_Array;
      Count : out Natural;
      Ok    : out Boolean)
     with Pre  => P in Text'Range and then Text'Last < Positive'Last
                  and then not Is_Blank (Text (P)),
          Post => P > P'Old and then Count <= Max_Pattern
   is
      C : UTF8.Code_Point;
   begin
      Codes := (others => 0);
      Dig := (others => 0);
      Count := 0;
      Ok := True;
      while P <= Text'Last and then not Is_Blank (Text (P)) loop
         pragma Loop_Invariant
           (P in Text'Range and then P >= P'Loop_Entry
            and then Count <= Max_Pattern);
         UTF8.Next_Code (Text, P, C);
         if C in Character'Pos ('0') .. Character'Pos ('9') then
            Dig (Count) := Unsigned_8 (C - Character'Pos ('0'));
         elsif Count < Max_Pattern then
            Count := Count + 1;
            Codes (Count) := C;
         else
            Ok := False;
         end if;
         exit when P > Text'Last;
      end loop;
   end Next_Pattern;

   procedure Measure (Text : String; Nodes, Pool_Size : out Natural) is
      P     : Positive := (if Text'Length > 0 then Text'First else 1);
      Found : Boolean;
      Codes : Pattern_Codes;
      Prev  : Pattern_Codes := (others => 0);
      Prev_Count : Natural := 0;
      Dig   : Digit_Array;
      Count : Natural;
      Ok    : Boolean;
      Same  : Natural;
   begin
      Nodes := 0;
      Pool_Size := 0;
      if Text'Length = 0 then
         return;
      end if;
      loop
         pragma Loop_Invariant
           (P >= Text'First and then Prev_Count <= Max_Pattern);
         Skip_Blanks (Text, P, Found);
         exit when not Found;
         --  Only the letters matter for the size: the digits are Build's.
         pragma Warnings
           (GNATprove, Off, """Dig"" is set by ""Next_Pattern"" but not used*",
            Reason => "Measure sizes the trie from the letters alone");
         Next_Pattern (Text, P, Codes, Dig, Count, Ok);
         pragma Warnings
           (GNATprove, On, """Dig"" is set by ""Next_Pattern"" but not used*");
         if Ok and then Count > 0 then
            --  Prefixes shared with the previous pattern need no new node.
            Same := 0;
            while Same < Count and then Same < Prev_Count
              and then Codes (Same + 1) = Prev (Same + 1)
            loop
               pragma Loop_Invariant (Same < Count and then Same < Prev_Count);
               Same := Same + 1;
            end loop;
            if Nodes < Natural'Last - Max_Pattern
              and then Pool_Size < Natural'Last - Max_Pattern - 1
            then
               Nodes := Nodes + (Count - Same);
               Pool_Size := Pool_Size + Count + 1;
            end if;
            Prev := Codes;
            Prev_Count := Count;
         end if;
         exit when P > Text'Last;
      end loop;
   end Measure;

   --  C's letter in T, 0 if the patterns do not use it.
   function Letter_Of (T : Trie; C : UTF8.Code_Point) return Letter is
   begin
      if C <= Direct_Last then
         return T.Map (C);
      end if;
      for I in 1 .. T.Extra_Count loop
         if T.Extra_Code (I) = C then
            return T.Extra_Letter (I);
         end if;
      end loop;
      return 0;
   end Letter_Of;

   --  C's letter in T, added to the alphabet if new (0 when it is full).
   procedure Add_Letter (T : in out Trie; C : UTF8.Code_Point; L : out Letter)
     with Post => T.Pool_Used = T.Pool_Used'Old
   is
   begin
      L := Letter_Of (T, C);
      if L /= 0 or else T.Alphabet = Letter'Last then
         return;
      end if;
      if C <= Direct_Last then
         T.Alphabet := T.Alphabet + 1;
         T.Map (C) := T.Alphabet;
         L := T.Alphabet;
      elsif T.Extra_Count < Max_Extra then
         T.Alphabet := T.Alphabet + 1;
         T.Extra_Count := T.Extra_Count + 1;
         T.Extra_Code (T.Extra_Count) := C;
         T.Extra_Letter (T.Extra_Count) := T.Alphabet;
         L := T.Alphabet;
      end if;
   end Add_Letter;

   --  The child of node N (0: the root) for letter L, 0 if none.
   function Child_Of (T : Trie; N : Natural; L : Letter) return Natural is
      C : Natural;
   begin
      if N = 0 then
         return T.Root (L);
      elsif N > T.Nodes then
         return 0;
      end if;
      C := T.Child (N);
      while C in 1 .. T.Nodes loop
         pragma Loop_Variant (Decreases => C);
         if T.Node_Letter (C) = L then
            return C;
         end if;
         --  A node is always made after the siblings it links to, so the
         --  list runs to lower numbers; anything else is not a trie Build
         --  made, and the search stops rather than follow a cycle.
         exit when T.Sibling (C) >= C;
         C := T.Sibling (C);
      end loop;
      return 0;
   end Child_Of;

   --  The child of N for L, made if there is none (0 when T is full).
   procedure Make_Child
     (T : in out Trie; N : Natural; L : Letter; Result : out Natural)
     with Post => T.Pool_Used = T.Pool_Used'Old
   is
   begin
      Result := Child_Of (T, N, L);
      if Result /= 0 or else T.Used >= T.Nodes then
         return;
      end if;
      T.Used := T.Used + 1;
      Result := T.Used;
      T.Node_Letter (Result) := L;
      T.Child (Result) := 0;
      T.Value (Result) := 0;
      if N = 0 then
         T.Sibling (Result) := 0;
         T.Root (L) := Result;
      elsif N <= T.Nodes then
         T.Sibling (Result) := T.Child (N);
         T.Child (N) := Result;
      else
         T.Sibling (Result) := 0;
      end if;
   end Make_Child;

   procedure Build
     (Text                : String;
      Left_Min, Right_Min : Positive;
      T                   : in out Trie;
      Ok                  : out Boolean)
   is
      P       : Positive := (if Text'Length > 0 then Text'First else 1);
      Found   : Boolean;
      Codes   : Pattern_Codes;
      Dig     : Digit_Array;
      Count   : Natural;
      Good    : Boolean;
      N       : Natural;
      L       : Letter;
      Added   : Boolean := False;   --  a pattern went in
   begin
      --  Loops, not aggregates: T is large and on the heap.
      T.Left_Min := Left_Min;
      T.Right_Min := Right_Min;
      T.Used := 0;
      T.Pool_Used := 0;
      T.Alphabet := 0;
      T.Extra_Count := 0;
      for C in T.Map'Range loop
         T.Map (C) := 0;
      end loop;
      for I in T.Root'Range loop
         T.Root (I) := 0;
      end loop;
      Ok := False;
      if Text'Length = 0 then
         return;
      end if;

      loop
         pragma Loop_Invariant
           (P >= Text'First and then T.Pool_Used <= T.Pool_Size);
         Skip_Blanks (Text, P, Found);
         exit when not Found;
         Next_Pattern (Text, P, Codes, Dig, Count, Good);
         if Good and then Count > 0
           and then T.Pool_Used < T.Pool_Size
           and then Count + 1 <= T.Pool_Size - T.Pool_Used
         then
            N := 0;
            for I in 1 .. Count loop
               pragma Loop_Invariant (T.Pool_Used = T.Pool_Used'Loop_Entry);
               Add_Letter (T, Codes (I), L);
               if L = 0 then
                  return;   --  more than 255 letters
               end if;
               Make_Child (T, N, L, N);
               exit when N = 0;
            end loop;
            if N in 1 .. T.Nodes then
               T.Value (N) := T.Pool_Used + 1;
               for I in 0 .. Count loop
                  T.Pool (T.Pool_Used + 1 + I) := Dig (I);
               end loop;
               T.Pool_Used := T.Pool_Used + Count + 1;
               Added := True;
            end if;
         end if;
         exit when P > Text'Last;
      end loop;
      Ok := Added;
   end Build;

   procedure Hyphenate
     (T      : Trie;
      Word   : Code_Array;
      Breaks : out Break_Array)
   is
      N    : constant Natural := Word'Length;
      Dot  : constant Letter := Letter_Of (T, Character'Pos ('.'));
      --  The word between two word-boundary dots: letters 0 .. N + 1.
      Pad  : array (0 .. Max_Word + 1) of Letter := (others => 0);
      --  Val (I): the highest digit seen before padded letter I.
      Val  : array (0 .. Max_Word + 2) of Unsigned_8 := (others => 0);
      Node : Natural;
      J    : Natural;
      At_V : Natural;
   begin
      Breaks := (others => False);
      if N < T.Left_Min or else N - T.Left_Min < T.Right_Min then
         return;
      end if;
      Pad (0) := Dot;
      Pad (N + 1) := Dot;
      for I in 1 .. N loop
         Pad (I) := Letter_Of (T, Fold (Word (I)));
         if Pad (I) = 0 then
            return;   --  a letter the patterns do not know
         end if;
      end loop;

      for S in 0 .. N + 1 loop
         J := S;
         Node := Child_Of (T, 0, Pad (S));
         while Node in 1 .. T.Nodes loop
            pragma Loop_Invariant (J in S .. N + 1);
            At_V := T.Value (Node);
            if At_V > 0 then
               --  A pattern of J - S + 1 letters matches at S.
               for D in 0 .. J - S + 1 loop
                  exit when D > T.Pool_Size - At_V;
                  if T.Pool (At_V + D) > Val (S + D) then
                     Val (S + D) := T.Pool (At_V + D);
                  end if;
               end loop;
            end if;
            exit when J = N + 1;
            J := J + 1;
            Node := Child_Of (T, Node, Pad (J));
         end loop;
      end loop;

      --  After letter I is before padded letter I + 1.
      for I in T.Left_Min .. N - T.Right_Min loop
         Breaks (I) := Val (I + 1) mod 2 = 1;
      end loop;
   end Hyphenate;

   function Is_Letter (C : UTF8.Code_Point) return Boolean is
     (C in Character'Pos ('A') .. Character'Pos ('Z')
      or else C in Character'Pos ('a') .. Character'Pos ('z')
      or else (C in 16#C0# .. 16#24F# and then C /= 16#D7# and then C /= 16#F7#)
      or else C = 16#386#
      or else (C in 16#388# .. 16#3FF# and then C /= 16#3F6#)
      or else C in 16#400# .. 16#481#
      or else C in 16#48A# .. 16#52F#);

   function Fold (C : UTF8.Code_Point) return UTF8.Code_Point is
   begin
      if C in Character'Pos ('A') .. Character'Pos ('Z')
        or else (C in 16#C0# .. 16#DE# and then C /= 16#D7#)
        or else (C in 16#391# .. 16#3AB# and then C /= 16#3A2#)
        or else C in 16#410# .. 16#42F#
      then
         return C + 32;
      elsif C = 16#130# then
         return Character'Pos ('i');
      elsif C = 16#178# then
         return 16#FF#;
      elsif (C in 16#100# .. 16#137# or else C in 16#14A# .. 16#177#
             or else C in 16#460# .. 16#481# or else C in 16#48A# .. 16#4BF#
             or else C in 16#4D0# .. 16#52F#)
        and then C mod 2 = 0
      then
         return C + 1;
      elsif (C in 16#139# .. 16#148# or else C in 16#179# .. 16#17E#
             or else C in 16#4C1# .. 16#4CE#)
        and then C mod 2 = 1
      then
         return C + 1;
      elsif C in 16#400# .. 16#40F# then
         return C + 80;
      elsif C = 16#386# then
         return 16#3AC#;
      elsif C in 16#388# .. 16#38A# then
         return C + 37;
      elsif C = 16#38C# then
         return 16#3CC#;
      elsif C in 16#38E# .. 16#38F# then
         return C + 63;
      else
         return C;
      end if;
   end Fold;

end Hyphenation;
