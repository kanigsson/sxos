package body Store_Log
  with SPARK_Mode => On
is
   use Store_Record;

   Signature : constant := 16#3153_5853#;   --  "SXS1"

   type Entry_Type is record
      Used  : Boolean := False;
      K     : Key;
      P     : Payload := (others => 0);
      Stamp : Unsigned_32 := 0;   --  write order: higher is newer
   end record;

   subtype Entry_Index is Positive range 1 .. Max_Entries;
   type Entry_Array is array (Entry_Index) of Entry_Type;

   Table  : Entry_Array;
   Clock  : Unsigned_32 := 0;     --  the next stamp

   Active : Natural range 0 .. 1 := 0;
   Gen    : Unsigned_32 := 0;
   Next   : Natural range 0 .. Slots := Slots;  --  first free slot
   Flash_Ok : Boolean := False;

   function Generation return Unsigned_32 is (Gen);
   function Used_Slots return Natural is (Next);

   --  Counted on demand: a running count would be a second copy of what the
   --  Used flags already say.
   function Entries return Natural is
      N : Natural := 0;
   begin
      for I in Entry_Index loop
         pragma Loop_Invariant (N < I);
         if Table (I).Used then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Entries;

   function Slot_Addr (Block : Natural; Slot : Natural) return Unsigned_32 is
     (Base + Unsigned_32 (Block) * Block_Size
      + Unsigned_32 (Slot) * Store_Record.Size)
     with Pre => Block <= 1 and then Slot < Slots;

   function Find (K : Key) return Natural
     with Post => Find'Result <= Max_Entries
   is
   begin
      for I in Entry_Index loop
         if Table (I).Used and then Table (I).K = K then
            return I;
         end if;
      end loop;
      return 0;
   end Find;

   --  Record K => P in the table, as the newest entry.
   procedure Remember (K : Key; P : Payload) is
      I      : Natural := Find (K);
      Oldest : Unsigned_32 := Unsigned_32'Last;
   begin
      if I = 0 then
         for J in Entry_Index loop
            if not Table (J).Used then
               I := J;
               exit;
            end if;
         end loop;
      end if;
      if I = 0 then
         --  Full: forget the least recently written position.
         for J in Entry_Index loop
            pragma Loop_Invariant (I <= Max_Entries);
            if Table (J).K.Kind /= Settings and then Table (J).Stamp < Oldest
            then
               Oldest := Table (J).Stamp;
               I := J;
            end if;
         end loop;
      end if;
      if I /= 0 then
         Table (I) := (Used => True, K => K, P => P, Stamp => Clock);
         Clock := Clock + 1;
      end if;
   end Remember;

   procedure Read_Header
     (Block : Natural; Valid : out Boolean; G : out Unsigned_32)
     with Pre => Block <= 1
   is
      R    : Image;
      K    : Key;
      P    : Payload;
      Ok   : Boolean;
   begin
      Read (Slot_Addr (Block, 0), R, Ok);
      --  A header's payload is unused: only its key carries information.
      pragma Warnings
        (GNATprove, Off, """P"" is set by ""Decode"" but not used after the call",
         Reason => "a header record has no payload");
      Decode (R, K, P, Valid);
      pragma Warnings
        (GNATprove, On, """P"" is set by ""Decode"" but not used after the call");
      Valid := Ok and then Valid and then K.Kind = Header
        and then K.A = Signature;
      G := (if Valid then K.B else 0);
   end Read_Header;

   procedure Write_Header (Block : Natural; G : Unsigned_32; Ok : out Boolean)
     with Pre => Block <= 1
   is
      R : Image;
   begin
      Encode ((Kind => Header, A => Signature, B => G), (others => 0), R);
      Program (Slot_Addr (Block, 0), R, Ok);
   end Write_Header;

   procedure Erase_Block (Block : Natural; Ok : out Boolean)
     with Pre => Block <= 1
   is
   begin
      for S in 0 .. Block_Size / Sector_Size - 1 loop
         Erase (Base + Unsigned_32 (Block) * Block_Size
                + Unsigned_32 (S) * Sector_Size, Ok);
         exit when not Ok;
      end loop;
   end Erase_Block;

   --  Load the active block's records into the table, and find Next.
   procedure Scan is
      Chunk_Slots : constant := 16;
      --  Cleared up front: the reads below each fill a prefix of it.
      Buf  : Bytes.Byte_Array (0 .. Chunk_Slots * Store_Record.Size - 1) :=
        [others => 0];
      R    : Image;
      K    : Key;
      P    : Payload;
      Valid, Ok : Boolean;
      Slot : Natural := 1;
      N    : Natural;
   begin
      Next := Slots;
      while Slot < Slots loop
         pragma Loop_Invariant (Slot >= 1);
         N := Natural'Min (Chunk_Slots, Slots - Slot);
         Read (Slot_Addr (Active, Slot), Buf (0 .. N * Store_Record.Size - 1),
               Ok);
         if not Ok then
            Flash_Ok := False;
            return;
         end if;
         for J in 0 .. N - 1 loop
            R := Buf (J * Store_Record.Size
                      .. J * Store_Record.Size + Store_Record.Size - 1);
            if Is_Free (R) then
               Next := Slot + J;
               return;
            end if;
            Decode (R, K, P, Valid);
            if Valid and then K.Kind /= Header then
               Remember (K, P);
            end if;
         end loop;
         Slot := Slot + N;
      end loop;
   end Scan;

   procedure Format (Ok : out Boolean) is
   begin
      Active := 0;
      Gen := 1;
      Erase_Block (0, Ok);
      if Ok then
         Write_Header (0, Gen, Ok);
      end if;
      Next := 1;
   end Format;

   procedure Mount (Ok : out Boolean) is
      V0, V1 : Boolean;
      G0, G1 : Unsigned_32;
   begin
      for E of Table loop
         E.Used := False;
      end loop;
      Clock := 0;
      Read_Header (0, V0, G0);
      Read_Header (1, V1, G1);
      if not V0 and then not V1 then
         Format (Ok);
      else
         Active := (if V1 and then (not V0 or else G1 > G0) then 1 else 0);
         Gen := (if Active = 1 then G1 else G0);
         Flash_Ok := True;
         Scan;
         Ok := Flash_Ok;
      end if;
      Flash_Ok := Ok;
   end Mount;

   procedure Lookup (K : Key; P : out Payload; Found : out Boolean) is
      I : constant Natural := Find (K);
   begin
      Found := I /= 0;
      P := (if Found then Table (I).P else (others => 0));
   end Lookup;

   --  Write every live entry, oldest first, to the other block and make it
   --  active.
   procedure Compact (Ok : out Boolean) is
      Other : constant Natural := 1 - Active;
      Slot  : Natural := 1;
      Done  : array (Entry_Index) of Boolean := (others => False);
      Pick  : Natural;
      R     : Image;
   begin
      Erase_Block (Other, Ok);
      if not Ok then
         return;
      end if;
      loop
         pragma Loop_Invariant (Slot in 1 .. Slots);
         Pick := 0;
         for I in Entry_Index loop
            pragma Loop_Invariant (Pick <= Max_Entries);
            if Table (I).Used and then not Done (I)
              and then (Pick = 0 or else Table (I).Stamp < Table (Pick).Stamp)
            then
               Pick := I;
            end if;
         end loop;
         exit when Pick = 0 or else Slot >= Slots;
         Done (Pick) := True;
         Encode (Table (Pick).K, Table (Pick).P, R);
         Program (Slot_Addr (Other, Slot), R, Ok);
         if not Ok then
            return;
         end if;
         Slot := Slot + 1;
      end loop;
      Write_Header (Other, Gen + 1, Ok);
      if Ok then
         Active := Other;
         Gen := Gen + 1;
         Next := Slot;
      end if;
   end Compact;

   procedure Put (K : Key; P : Payload; Ok : out Boolean) is
      I : constant Natural := Find (K);
      R : Image;
   begin
      Ok := True;
      if I /= 0 and then Table (I).P = P then
         return;
      end if;
      Remember (K, P);
      if not Flash_Ok then
         Ok := False;
         return;
      end if;
      if Next >= Slots then
         Compact (Ok);   --  writes the new entry along with the rest
      else
         Encode (K, P, R);
         Program (Slot_Addr (Active, Next), R, Ok);
         Next := Next + 1;   --  a failed write still used up the slot
      end if;
   end Put;

end Store_Log;
