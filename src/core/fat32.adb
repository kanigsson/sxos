with UTF8;

package body Fat32
  with SPARK_Mode => On
is
   use type Bytes.Byte;

   End_Of_Chain : constant Unsigned_32 := 16#0FFF_FFF8#;

   function U16 (B : Sector; I : Natural) return Unsigned_32 is
     (Unsigned_32 (B (I)) or Shift_Left (Unsigned_32 (B (I + 1)), 8))
     with Pre => I < Block_Size - 1;

   function U32 (B : Sector; I : Natural) return Unsigned_32 is
     (Unsigned_32 (B (I)) or Shift_Left (Unsigned_32 (B (I + 1)), 8)
      or Shift_Left (Unsigned_32 (B (I + 2)), 16)
      or Shift_Left (Unsigned_32 (B (I + 3)), 24))
     with Pre => I < Block_Size - 3;

   function Valid (V : Volume; C : Unsigned_32) return Boolean is
     (C >= 2 and then Unsigned_64 (C) < Unsigned_64 (V.Clusters) + 2);

   function Cluster_LBA (V : Volume; C : Unsigned_32) return Unsigned_32 is
     (V.Data_Start + (C - 2) * V.Per_Cluster);

   function Root (V : Volume) return File is
     (First => V.Root_Cluster, Size => 0, Directory => True,
      Cur_Index => 0, Cur => V.Root_Cluster);

   -----------
   -- Mount --
   -----------

   --  Does B look like a FAT32 boot sector?  (Jump opcode, 512-byte blocks,
   --  no FAT16 size field, a FAT32 size, and the boot signature.)
   function Is_Fat32_Boot (B : Sector) return Boolean is
     ((B (0) = 16#EB# or else B (0) = 16#E9#)
      and then U16 (B, 11) = Block_Size
      and then U16 (B, 22) = 0
      and then U32 (B, 36) /= 0
      and then B (510) = 16#55# and then B (511) = 16#AA#);

   procedure Mount (V : out Volume; Status : out Mount_Status) is
      Part : Unsigned_32 := 0;
      Read_Ok : Boolean;
   begin
      V := (Mounted => False, Fat_Start => 0, Fat_Size => 0, Data_Start => 0,
            Per_Cluster => 1, Clusters => 0, Root_Cluster => 2,
            Fat_Cache => (others => 0), Fat_Cache_LBA => Unsigned_32'Last,
            Buf => (others => 0));

      Read_Blocks (0, V.Buf, Read_Ok);
      if not Read_Ok then
         Status := Read_Error;
         return;
      end if;
      if V.Buf (510) /= 16#55# or else V.Buf (511) /= 16#AA# then
         Status := Unsupported_FS;
         return;
      end if;

      --  A superfloppy has the boot sector at 0; otherwise take the first
      --  FAT32 (0x0B CHS / 0x0C LBA) entry of the MBR partition table.
      if not Is_Fat32_Boot (V.Buf) then
         for P in 0 .. 3 loop
            declare
               E : constant Natural := 446 + 16 * P;
            begin
               if V.Buf (E + 4) = 16#0B# or else V.Buf (E + 4) = 16#0C# then
                  Part := U32 (V.Buf, E + 8);
                  exit;
               end if;
            end;
         end loop;
         if Part = 0 then
            Status := Unsupported_FS;
            return;
         end if;
         Read_Blocks (Part, V.Buf, Read_Ok);
         if not Read_Ok then
            Status := Read_Error;
            return;
         end if;
         if not Is_Fat32_Boot (V.Buf) then
            Status := Unsupported_FS;
            return;
         end if;
      end if;

      declare
         SPC      : constant Unsigned_32 := Unsigned_32 (V.Buf (13));
         Reserved : constant Unsigned_32 := U16 (V.Buf, 14);
         N_Fats   : constant Unsigned_32 := Unsigned_32 (V.Buf (16));
         Total    : constant Unsigned_32 :=
           (if U16 (V.Buf, 19) /= 0 then U16 (V.Buf, 19) else U32 (V.Buf, 32));
         Fat_Sz   : constant Unsigned_32 := U32 (V.Buf, 36);
         Overhead : Unsigned_64;
      begin
         if SPC = 0 or else (SPC and (SPC - 1)) /= 0 or else Reserved = 0
           or else N_Fats = 0 or else N_Fats > 2 or else U16 (V.Buf, 17) /= 0
         then
            Status := Invalid_FS;
            return;
         end if;
         Overhead := Unsigned_64 (Reserved) + Unsigned_64 (N_Fats) * Unsigned_64 (Fat_Sz);
         if Overhead >= Unsigned_64 (Total) then
            Status := Invalid_FS;
            return;
         end if;
         V.Per_Cluster  := SPC;
         V.Fat_Start    := Part + Reserved;
         V.Fat_Size     := Fat_Sz;
         V.Data_Start   := Part + Unsigned_32 (Overhead);
         V.Clusters     := (Total - Unsigned_32 (Overhead)) / SPC;
         V.Root_Cluster := U32 (V.Buf, 44);
         --  The FAT must be able to describe every cluster.
         if Unsigned_64 (V.Clusters + 2) * 4
              > Unsigned_64 (Fat_Sz) * Block_Size
           or else not Valid (V, V.Root_Cluster)
         then
            Status := Invalid_FS;
            return;
         end if;
      end;

      V.Mounted := True;
      Status := OK;
   end Mount;

   ------------------
   -- Next_Cluster --
   ------------------

   procedure Next_Cluster
     (V : in out Volume; C : Unsigned_32; Next : out Unsigned_32;
      Ok : out Boolean)
   is
      Offset : constant Unsigned_32 := C * 4;
      LBA    : constant Unsigned_32 := V.Fat_Start + Offset / Block_Size;
   begin
      Next := 0;
      if Offset / Block_Size >= V.Fat_Size then
         Ok := False;
         return;
      end if;
      if LBA /= V.Fat_Cache_LBA then
         Read_Blocks (LBA, V.Fat_Cache, Ok);
         if not Ok then
            V.Fat_Cache_LBA := Unsigned_32'Last;
            return;
         end if;
         V.Fat_Cache_LBA := LBA;
      end if;
      Next := U32 (V.Fat_Cache, Natural (Offset mod Block_Size))
        and 16#0FFF_FFFF#;
      Ok := True;
   end Next_Cluster;

   --  Move F's cursor to chain position Index (0 = First).
   procedure Seek
     (V : in out Volume; F : in out File; Index : Unsigned_32; Ok : out Boolean)
   is
      Next : Unsigned_32;
   begin
      Ok := True;
      if F.Cur_Index > Index or else not Valid (V, F.Cur) then
         F.Cur_Index := 0;
         F.Cur := F.First;
      end if;
      if not Valid (V, F.Cur) then
         Ok := False;
         return;
      end if;
      while F.Cur_Index < Index loop
         Next_Cluster (V, F.Cur, Next, Ok);
         if not Ok or else not Valid (V, Next) then
            Ok := False;
            return;
         end if;
         F.Cur := Next;
         F.Cur_Index := F.Cur_Index + 1;
      end loop;
   end Seek;

   ----------
   -- Read --
   ----------

   procedure Read
     (V      : in out Volume;
      F      : in out File;
      Offset : Unsigned_32;
      Into   : out Bytes.Byte_Array;
      Count  : out Natural;
      Ok     : out Boolean)
   is
      Cluster_Bytes : constant Unsigned_32 := V.Per_Cluster * Block_Size;
      Want : Natural;
      Pos  : Unsigned_32 := Offset;
   begin
      Count := 0;
      Ok := True;
      if Offset >= F.Size or else Into'Length = 0 then
         return;
      end if;
      Want := Natural (Unsigned_32'Min (Unsigned_32 (Into'Length), F.Size - Offset));

      while Count < Want loop
         Seek (V, F, Pos / Cluster_Bytes, Ok);
         exit when not Ok;
         declare
            In_Cluster : constant Unsigned_32 := Pos mod Cluster_Bytes;
            Blk        : constant Unsigned_32 := In_Cluster / Block_Size;
            In_Blk     : constant Natural := Natural (In_Cluster mod Block_Size);
            LBA        : constant Unsigned_32 := Cluster_LBA (V, F.Cur) + Blk;
            Remaining  : constant Natural := Want - Count;
            Dest       : constant Natural := Into'First + Count;
            N          : Natural;
         begin
            if In_Blk = 0 and then Remaining >= Block_Size then
               --  Whole blocks straight into the caller's buffer, up to the
               --  end of this cluster: one multi-block read.
               N := Block_Size * Natural'Min
                 (Remaining / Block_Size, Natural (V.Per_Cluster - Blk));
               Read_Blocks (LBA, Into (Dest .. Dest + N - 1), Ok);
            else
               Read_Blocks (LBA, V.Buf, Ok);
               N := Natural'Min (Block_Size - In_Blk, Remaining);
               if Ok then
                  Into (Dest .. Dest + N - 1) := V.Buf (In_Blk .. In_Blk + N - 1);
               end if;
            end if;
            exit when not Ok;
            Count := Count + N;
            Pos := Pos + Unsigned_32 (N);
         end;
      end loop;
   end Read;

   -------------
   -- Iterate --
   -------------

   procedure Iterate (V : in out Volume; Dir : File; Ok : out Boolean) is
      --  Long-name assembly.  Slots arrive last-first; each carries 13 UTF-16
      --  units and the checksum of the short entry they belong to.
      Units    : array (1 .. 260) of Unsigned_32 := (others => 0);
      Total    : Natural := 0;      --  slots in the current long name
      Expected : Natural := 0;      --  next slot number we are waiting for
      Sum      : Bytes.Byte := 0;
      Offsets  : constant array (1 .. 13) of Natural :=
        (1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30);

      Name : String (1 .. Max_Name);
      Last : Natural;
      C    : Unsigned_32 := Dir.First;
      Next : Unsigned_32;
      Stop : Boolean := False;

      function Checksum (I : Natural) return Bytes.Byte is
         S : Bytes.Byte := 0;
      begin
         for K in 0 .. 10 loop
            S := Rotate_Right (S, 1) + V.Buf (I + K);
         end loop;
         return S;
      end Checksum;

      procedure Short_Name (I : Natural) is
         Flags : constant Bytes.Byte := V.Buf (I + 12);
         procedure Put (B : Bytes.Byte; Lower : Boolean) is
            Code : Natural := Natural (B);
         begin
            if Lower and then Code in Character'Pos ('A') .. Character'Pos ('Z') then
               Code := Code + 32;
            end if;
            UTF8.Append (Name, Last, UTF8.Code_Point (Code));
         end Put;
         Base_Last : Integer := 7;
         Ext_Last  : Integer := 10;
      begin
         while Base_Last >= 0 and then V.Buf (I + Base_Last) = 16#20# loop
            Base_Last := Base_Last - 1;
         end loop;
         while Ext_Last >= 8 and then V.Buf (I + Ext_Last) = 16#20# loop
            Ext_Last := Ext_Last - 1;
         end loop;
         for K in 0 .. Base_Last loop
            Put ((if K = 0 and then V.Buf (I) = 16#05# then 16#E5#
                  else V.Buf (I + K)), (Flags and 16#08#) /= 0);
         end loop;
         if Ext_Last >= 8 then
            UTF8.Append (Name, Last, Character'Pos ('.'));
            for K in 8 .. Ext_Last loop
               Put (V.Buf (I + K), (Flags and 16#10#) /= 0);
            end loop;
         end if;
      end Short_Name;

      procedure Long_Name is
         K : Natural := 1;
         U : Unsigned_32;
      begin
         while K <= Total * 13 loop
            U := Units (K);
            exit when U = 0 or else U = 16#FFFF#;
            if U in 16#D800# .. 16#DBFF# and then K < Total * 13
              and then Units (K + 1) in 16#DC00# .. 16#DFFF#
            then
               UTF8.Append
                 (Name, Last, UTF8.Code_Point
                    (16#1_0000# + (U - 16#D800#) * 1024 + (Units (K + 1) - 16#DC00#)));
               K := K + 2;
            else
               UTF8.Append (Name, Last, UTF8.Code_Point (U));
               K := K + 1;
            end if;
         end loop;
      end Long_Name;

   begin
      Ok := True;
      for Step in 1 .. V.Clusters loop
         if not Valid (V, C) then
            Ok := False;
            return;
         end if;
         for B in 0 .. V.Per_Cluster - 1 loop
            Read_Blocks (Cluster_LBA (V, C) + B, V.Buf, Ok);
            if not Ok then
               return;
            end if;
            for Slot in 0 .. Block_Size / 32 - 1 loop
               declare
                  I    : constant Natural := Slot * 32;
                  Attr : constant Bytes.Byte := V.Buf (I + 11);
               begin
                  if V.Buf (I) = 0 then
                     return;                          --  end of directory
                  elsif V.Buf (I) = 16#E5# then
                     Total := 0; Expected := 0;       --  deleted
                  elsif Attr = 16#0F# then
                     declare
                        Ord : constant Natural := Natural (V.Buf (I) and 16#1F#);
                     begin
                        if (V.Buf (I) and 16#40#) /= 0 and then Ord in 1 .. 20 then
                           Total := Ord; Expected := Ord; Sum := V.Buf (I + 13);
                           Units := (others => 0);
                        end if;
                        if Expected > 0 and then Ord = Expected
                          and then V.Buf (I + 13) = Sum
                        then
                           for J in Offsets'Range loop
                              Units ((Ord - 1) * 13 + J) :=
                                U16 (V.Buf, I + Offsets (J));
                           end loop;
                           Expected := Expected - 1;
                        else
                           Total := 0; Expected := 0;
                        end if;
                     end;
                  elsif (Attr and 16#08#) /= 0 or else V.Buf (I) = 16#2E# then
                     Total := 0; Expected := 0;       --  label, "." or ".."
                  else
                     Last := 0;
                     if Total > 0 and then Expected = 0 and then Checksum (I) = Sum
                     then
                        Long_Name;
                     end if;
                     if Last = 0 then
                        Short_Name (I);
                     end if;
                     Total := 0; Expected := 0;
                     declare
                        First : constant Unsigned_32 :=
                          Shift_Left (U16 (V.Buf, I + 20), 16) or U16 (V.Buf, I + 26);
                     begin
                        Visit (Name (1 .. Last),
                               (First => First, Size => U32 (V.Buf, I + 28),
                                Directory => (Attr and 16#10#) /= 0,
                                Cur_Index => 0, Cur => First),
                               Stop);
                     end;
                     if Stop then
                        return;
                     end if;
                  end if;
               end;
            end loop;
         end loop;
         Next_Cluster (V, C, Next, Ok);
         if not Ok or else Next >= End_Of_Chain then
            return;
         end if;
         C := Next;
      end loop;
   end Iterate;

   ----------
   -- Open --
   ----------

   function Lower (C : Character) return Character is
     (if C in 'A' .. 'Z' then Character'Val (Character'Pos (C) + 32) else C);

   function Same_Name (A, B : String) return Boolean is
     (A'Length = B'Length
      and then (for all K in 0 .. A'Length - 1 =>
                  Lower (A (A'First + K)) = Lower (B (B'First + K))));

   procedure Open
     (V     : in out Volume;
      Path  : String;
      F     : out File;
      Found : out Boolean)
   is
      Cur   : File := Root (V);
      P     : Natural := Path'First;
      Q     : Natural;
      Ok    : Boolean;
   begin
      F := Cur;
      Found := V.Mounted;
      while Found and then P <= Path'Last loop
         Q := P;
         while Q <= Path'Last and then Path (Q) /= '/' loop
            Q := Q + 1;
         end loop;
         if Q > P then
            if not Cur.Directory then
               Found := False;
               return;
            end if;
            declare
               Want : constant String := Path (P .. Q - 1);
               Hit  : Boolean := False;
               Got  : File := Cur;

               procedure Match (Name : String; E : File; Stop : out Boolean) is
               begin
                  Stop := Same_Name (Name, Want);
                  if Stop then
                     Hit := True;
                     Got := E;
                  end if;
               end Match;

               procedure Search is new Iterate (Match);
            begin
               Search (V, Cur, Ok);
               Found := Ok and then Hit;
               Cur := Got;
            end;
         end if;
         P := Q + 1;
      end loop;
      if Found then
         F := Cur;
      end if;
   end Open;

end Fat32;
