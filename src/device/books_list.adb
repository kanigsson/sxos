with Interfaces; use Interfaces;
with ESP32S3.GPIO;
with ESP32S3.SDMMC;
with ESP32S3.Log; use ESP32S3.Log;

package body Books_List is
   use type ESP32S3.SDMMC.Status;
   subtype Byte is Unsigned_8;
   subtype Word is Unsigned_32;
   subtype Sector is ESP32S3.SDMMC.Block;
   Card : ESP32S3.SDMMC.Card;

   function U16 (B : Sector; I : Natural) return Natural is
     (Natural (B (I)) + 256 * Natural (B (I + 1)));
   function U32 (B : Sector; I : Natural) return Word is
     (Word (B (I)) or Shift_Left (Word (B (I + 1)), 8) or
      Shift_Left (Word (B (I + 2)), 16) or Shift_Left (Word (B (I + 3)), 24));

   procedure Load (Items : out Entries; Count : out Natural; Result : out Result_Kind) is
      B, Fat : Sector;
      SD_Status : ESP32S3.SDMMC.Status;
      Partition, Total, Fat_Start, Data_Start, Fat_Size, Clusters : Word := 0;
      Root : Word := 0;
      SPC : Natural := 0;
      Found_Books : Boolean := False;
      Books : Word := 0;
      Failed : Boolean := False;
      Fat_LBA : Word := Word'Last;

      procedure Read (LBA : Word; Into : out Sector) is
      begin
         if Unsigned_64 (LBA) >= ESP32S3.SDMMC.Capacity_Blocks (Card) then
            Failed := True;
            return;
         end if;
         ESP32S3.SDMMC.Read_Block
           (Card, ESP32S3.SDMMC.Block_Address (LBA), Into, SD_Status);
         if SD_Status /= ESP32S3.SDMMC.OK then
            Failed := True;
         end if;
      end Read;

      function Valid_Cluster (C : Word) return Boolean is
        (C >= 2 and then Unsigned_64 (C) < Unsigned_64 (Clusters) + 2);

      function Next_Cluster (C : Word) return Word is
         Offset : constant Word := C * 4;
         LBA : constant Word := Fat_Start + Offset / 512;
      begin
         if Offset / 512 >= Fat_Size then
            Failed := True;
            return 0;
         end if;
         if LBA /= Fat_LBA then
            Read (LBA, Fat);
            if Failed then return 0; end if;
            Fat_LBA := LBA;
         end if;
         return U32 (Fat, Natural (Offset mod 512)) and 16#0FFF_FFFF#;
      end Next_Cluster;

      function Equal_Books (S : String) return Boolean is
         T : constant String := "Books";
      begin
         if S'Length /= T'Length then return False; end if;
         for I in T'Range loop
            declare
               C : Character := S (S'First + I - 1);
            begin
               if C in 'a' .. 'z' then
                  C := Character'Val (Character'Pos (C) - 32);
               end if;
               if C /= Character'Val (Character'Pos (T (I)) -
                                      (if T (I) in 'a' .. 'z' then 32 else 0)) then
                  return False;
               end if;
            end;
         end loop;
         return True;
      end Equal_Books;

      --  Walk the root to locate Books, then its cluster chain to list it.
      --  Never read past a declared cluster count, even for a cyclic FAT.
      procedure Scan (First : Word; Looking_For_Books : Boolean) is
         C : Word := First;
         Next : Word;
         Raw : Sector;
         Name : String (1 .. 255) := (others => ' ');
         LFN : String (1 .. 255) := (others => ' ');
         LFN_Length : Natural := 0;
         LFN_Order : Natural := 0;
         LFN_Check : Byte := 0;
         Short_Name : String (1 .. 12);
         Last : Natural;
         Attr : Byte;
         Check : Byte;
         Ord : Natural;
         Pos : Natural;
         Code : Natural;
         Start : Word;
         --  Positions of the 13 UTF-16 characters within an LFN slot.
         Offsets : constant array (1 .. 13) of Natural :=
           (1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30);
      begin
         if not Valid_Cluster (C) then Failed := True; return; end if;
         for Chain_Step in 1 .. Natural (Clusters) loop
            for S in 0 .. SPC - 1 loop
               Read (Data_Start + (C - 2) * Word (SPC) + Word (S), Raw);
               if Failed then return; end if;
               for Slot in 0 .. 15 loop
                  declare
                     I : constant Natural := Slot * 32;
                  begin
                     if Raw (I) = 0 then return; end if;
                     if Raw (I) = 16#E5# then
                        LFN_Order := 0;
                     elsif Raw (I + 11) = 16#0F# then
                        Ord := Natural (Raw (I) and 16#1F#);
                        if Ord in 1 .. 20 and then Raw (I + 12) = 0 and then
                           U16 (Raw, I + 26) = 0 and then
                           ((Raw (I) and 16#40#) /= 0 or else
                            (LFN_Order = Ord + 1 and then LFN_Check = Raw (I + 13)))
                        then
                           if (Raw (I) and 16#40#) /= 0 then
                              LFN := (others => ' ');
                              LFN_Length := 0;
                              LFN_Check := Raw (I + 13);
                           end if;
                           for K in Offsets'Range loop
                              Pos := (Ord - 1) * 13 + K;
                              Code := U16 (Raw, I + Offsets (K));
                              if Pos <= LFN'Last and then Code /= 0 and then Code /= 16#FFFF# then
                                 LFN (Pos) := (if Code in 32 .. 126 then Character'Val (Code) else '?');
                                 LFN_Length := Natural'Max (LFN_Length, Pos);
                              end if;
                           end loop;
                           LFN_Order := Ord;
                        else
                           LFN_Order := 0;
                        end if;
                     else
                        Attr := Raw (I + 11);
                        if (Attr and 16#08#) = 0 then -- skip volume labels
                           Check := 0;
                           for K in 0 .. 10 loop
                              Check := Shift_Right (Check, 1) or Shift_Left (Check and 1, 7);
                              Check := Check + Raw (I + K);
                           end loop;
                           Short_Name := (others => ' ');
                           Last := 0;
                           for K in 0 .. 7 loop
                              if Raw (I + K) /= 32 then
                                 Last := Last + 1;
                                 Short_Name (Last) := Character'Val (Raw (I + K));
                              end if;
                           end loop;
                           if Raw (I + 8) /= 32 then
                              Last := Last + 1;
                              Short_Name (Last) := '.';
                              for K in 8 .. 10 loop
                                 if Raw (I + K) /= 32 then
                                    Last := Last + 1;
                                    Short_Name (Last) := Character'Val (Raw (I + K));
                                 end if;
                              end loop;
                           end if;
                           if LFN_Order = 1 and then LFN_Check = Check and then LFN_Length > 0 then
                              Name (1 .. LFN_Length) := LFN (1 .. LFN_Length);
                              Last := LFN_Length;
                           else
                              Name (1 .. Last) := Short_Name (1 .. Last);
                           end if;
                           Start := Word (U16 (Raw, I + 26)) or
                             Shift_Left (Word (U16 (Raw, I + 20)), 16);
                           if Looking_For_Books then
                              if (Attr and 16#10#) /= 0 and then Equal_Books (Name (1 .. Last)) then
                                 Books := Start;
                                 Found_Books := True;
                                 return;
                              end if;
                           elsif Last > 0 and then Name (1) /= '.' then
                              Count := Count + 1;
                              Items (Count).Last := Natural'Min (Last, Max_Chars);
                              Items (Count).Text (1 .. Items (Count).Last) :=
                                Name (1 .. Items (Count).Last);
                              if Last > Max_Chars then
                                 Items (Count).Text (Max_Chars - 2 .. Max_Chars) := "...";
                              end if;
                              Items (Count).Directory := (Attr and 16#10#) /= 0;
                              if Count = Max_Entries then return; end if;
                           end if;
                        end if;
                        LFN_Order := 0;
                     end if;
                  end;
               end loop;
            end loop;
            Next := Next_Cluster (C);
            if Failed then return; end if;
            if Next >= 16#0FFF_FFF8# then return; end if;
            if not Valid_Cluster (Next) then Failed := True; return; end if;
            C := Next;
         end loop;
         Failed := True; --  cyclic/overlong chain
      end Scan;
   begin
      Items := (others => (others => <>));
      Count := 0;
      Result := Card_Error;
      --  OEM mount sequence: GPIO5 active-low gate, HIGH 80 ms then LOW
      --  120 ms. Retry both initialization AND a sector-0 read, since a card
      --  can identify successfully while its data path is still settling.
      ESP32S3.GPIO.Configure (5, ESP32S3.GPIO.Output);
      for Attempt in 1 .. 4 loop
         ESP32S3.GPIO.Set (5);
         delay 0.080;
         ESP32S3.GPIO.Clear (5);
         delay 0.120;
         ESP32S3.SDMMC.Setup
           (Card, On => ESP32S3.SDMMC.Slot1, Clk => 41, Cmd => 42, D0 => 40,
            Width => ESP32S3.SDMMC.Width_1, Data_Clock_Hz => 20_000_000);
         ESP32S3.SDMMC.Initialize (Card, SD_Status);
         Put_Line ("[sxos] SD init: " & ESP32S3.SDMMC.Status'Image (SD_Status));
         if SD_Status = ESP32S3.SDMMC.OK then
            Result := Read_Error;
            Failed := False;
            Read (0, B);
            exit when not Failed;
         end if;
      end loop;
      if SD_Status /= ESP32S3.SDMMC.OK or else Failed then return; end if;
      if B (510) /= 16#55# or else B (511) /= 16#AA# then
         Result := Invalid_FS; return;
      end if;
      if (B (0) /= 16#EB# and then B (0) /= 16#E9#) or else
         U16 (B, 11) /= 512 or else U16 (B, 17) /= 0 then
         --  MBR: accept the first FAT32 partition only (0B/0C).
         Result := Unsupported_FS;
         for N in 0 .. 3 loop
            declare
               I : constant Natural := 446 + N * 16;
            begin
               if B (I + 4) = 16#0B# or else B (I + 4) = 16#0C# then
                  Partition := U32 (B, I + 8);
                  exit;
               end if;
            end;
         end loop;
         if Partition = 0 then return; end if;
         Read (Partition, B);
         if Failed then Result := Read_Error; return; end if;
      end if;
      Result := Invalid_FS;
      if B (510) /= 16#55# or else B (511) /= 16#AA# or else
         U16 (B, 11) /= 512 or else U16 (B, 17) /= 0 or else
         U16 (B, 22) /= 0 or else U16 (B, 14) = 0 or else
         B (16) = 0 or else U32 (B, 36) = 0 then
         return;
      end if;
      SPC := Natural (B (13));
      Total := U32 (B, 32);
      Fat_Size := U32 (B, 36);
      Root := U32 (B, 44);
      if SPC = 0 or else SPC > 128 or else (Word (SPC) and Word (SPC - 1)) /= 0 or else
         Total = 0 or else Unsigned_64 (Partition) + Unsigned_64 (Total) >
           ESP32S3.SDMMC.Capacity_Blocks (Card) or else
         Unsigned_64 (U16 (B, 14)) + Unsigned_64 (B (16)) * Unsigned_64 (Fat_Size) >= Unsigned_64 (Total) then
         return;
      end if;
      Fat_Start := Partition + Word (U16 (B, 14));
      Data_Start := Fat_Start + Word (B (16)) * Fat_Size;
      Clusters := (Partition + Total - Data_Start) / Word (SPC);
      if Clusters < 65_525 or else Unsigned_64 (Clusters) + 2 > Unsigned_64 (Fat_Size) * 128 then
         Result := Unsupported_FS; return;
      end if;
      Result := Read_Error;
      Scan (Root, True);
      if Failed then return; end if;
      if not Found_Books then Result := Books_Not_Found; return; end if;
      Scan (Books, False);
      if Failed then return; end if;
      Result := (if Count = 0 then Empty_Directory else OK);
   end Load;
end Books_List;
