package body Zip
  with SPARK_Mode => On
is

   function U16 (B : Bytes.Byte_Array; I : Natural) return Unsigned_32 is
     (Unsigned_32 (B (I)) or Shift_Left (Unsigned_32 (B (I + 1)), 8))
     with Pre  => I in B'Range and then I < B'Last,
          Post => U16'Result <= 16#FFFF#;

   function U32 (B : Bytes.Byte_Array; I : Natural) return Unsigned_32 is
     (Unsigned_32 (B (I)) or Shift_Left (Unsigned_32 (B (I + 1)), 8)
      or Shift_Left (Unsigned_32 (B (I + 2)), 16)
      or Shift_Left (Unsigned_32 (B (I + 3)), 24))
     with Pre => I in B'Range and then B'Last - I >= 3;

   End_Signature     : constant Unsigned_32 := 16#0605_4B50#;
   Central_Signature : constant Unsigned_32 := 16#0201_4B50#;
   Local_Signature   : constant Unsigned_32 := 16#0403_4B50#;
   Central_Size      : constant := 46;   --  fixed part of a directory entry

   procedure Find_Directory
     (Tail      : Bytes.Byte_Array;
      File_Size : Unsigned_32;
      Dir       : out Directory;
      Found     : out Boolean)
   is
   begin
      Dir := (others => <>);
      Found := False;
      if Tail'Length < 22 then
         return;
      end if;
      --  Search backwards: the record is last unless a comment follows it.
      for I in reverse Tail'First .. Tail'Last - 21 loop
         if U32 (Tail, I) = End_Signature then
            Dir := (Offset  => U32 (Tail, I + 16),
                    Size    => U32 (Tail, I + 12),
                    Entries => Natural (U16 (Tail, I + 10)));
            if Unsigned_64 (Dir.Offset) + Unsigned_64 (Dir.Size)
              <= Unsigned_64 (File_Size)
            then
               Found := True;
               return;
            end if;
         end if;
      end loop;
   end Find_Directory;

   function Lower (C : Character) return Character is
     (if C in 'A' .. 'Z'
      then Character'Val (Character'Pos (C) + 32) else C);

   procedure Find
     (Dir   : Bytes.Byte_Array;
      Name  : String;
      M     : out Member;
      Found : out Boolean)
   is
      P          : Natural;
      Name_Len   : Natural;
      Skip       : Unsigned_32;
      Exact, Folded : Boolean;
      Have_Folded : Boolean := False;
   begin
      M := (others => <>);
      Found := False;
      --  An empty Dir's bounds need not be Naturals.
      if Dir'Length = 0 then
         return;
      end if;
      P := Dir'First;
      while Dir'Last >= Central_Size - 1
        and then P <= Dir'Last - (Central_Size - 1)
        and then U32 (Dir, P) = Central_Signature
      loop
         pragma Loop_Invariant (P >= Dir'First);
         Name_Len := Natural (U16 (Dir, P + 28));
         Skip := Central_Size + Unsigned_32 (Name_Len) + U16 (Dir, P + 30)
                 + U16 (Dir, P + 32);
         exit when Unsigned_64 (P) + Unsigned_64 (Skip)
           > Unsigned_64 (Dir'Last) + 1;
         --  The entry, name included, lies within Dir.
         pragma Assert (Unsigned_64 (Skip)
                          >= Central_Size + Unsigned_64 (Name_Len));
         pragma Assert (P + (Central_Size - 1) + Name_Len <= Dir'Last);

         if Name_Len = Name'Length then
            Exact := True;
            Folded := True;
            for K in 0 .. Name_Len - 1 loop
               declare
                  A : constant Character :=
                    Character'Val (Dir (P + Central_Size + K));
                  B : constant Character := Name (Name'First + K);
               begin
                  if A /= B then
                     Exact := False;
                     if Lower (A) /= Lower (B) then
                        Folded := False;
                        exit;
                     end if;
                  end if;
               end;
            end loop;
            if Exact or else (Folded and then not Have_Folded) then
               M := (Method        => Natural (U16 (Dir, P + 10)),
                     CRC           => U32 (Dir, P + 16),
                     Compressed    => U32 (Dir, P + 20),
                     Size          => U32 (Dir, P + 24),
                     Header_Offset => U32 (Dir, P + 42));
               Found := True;
               Have_Folded := True;
               exit when Exact;
            end if;
         end if;
         exit when Unsigned_64 (P) + Unsigned_64 (Skip)
           > Unsigned_64 (Natural'Last);
         P := P + Natural (Skip);
      end loop;
   end Find;

   procedure Data_Offset
     (Header : Bytes.Byte_Array;
      M      : Member;
      Offset : out Unsigned_32;
      Ok     : out Boolean)
   is
      F : constant Natural := Header'First;
      Skip : Unsigned_64;
   begin
      Offset := 0;
      Ok := U32 (Header, F) = Local_Signature;
      if Ok then
         Skip := Unsigned_64 (M.Header_Offset) + Local_Header_Size
           + Unsigned_64 (U16 (Header, F + 26)) + Unsigned_64 (U16 (Header, F + 28));
         Ok := Skip <= Unsigned_64 (Unsigned_32'Last);
         if Ok then
            Offset := Unsigned_32 (Skip);
         end if;
      end if;
   end Data_Offset;
end Zip;
