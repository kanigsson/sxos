with ESP32S3.GPIO;
with ESP32S3.Log; use ESP32S3.Log;
with ESP32S3.SDMMC;

package body Card is
   use type ESP32S3.SDMMC.Status;
   use type Interfaces.Unsigned_64;

   Gate_Pin : constant ESP32S3.GPIO.Pin_Id := 5;   --  active-low card power
   SD       : ESP32S3.SDMMC.Card;
   Ready    : Boolean := False;

   procedure Read_Blocks
     (LBA : Interfaces.Unsigned_32; Data : out Bytes.Byte_Array; Ok : out Boolean)
   is
      Run    : ESP32S3.SDMMC.Block_Run (Data'Range)
        with Import, Address => Data'Address;
      Status : ESP32S3.SDMMC.Status;
      Blocks : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (Data'Length / 512);
   begin
      if not Ready
        or else Interfaces.Unsigned_64 (LBA) + Blocks
                  > ESP32S3.SDMMC.Capacity_Blocks (SD)
      then
         Ok := False;
         return;
      end if;
      ESP32S3.SDMMC.Read_Blocks (SD, ESP32S3.SDMMC.Block_Address (LBA), Run, Status);
      Ok := Status = ESP32S3.SDMMC.OK;
   end Read_Blocks;

   procedure Initialize (Ok : out Boolean) is
      Status : ESP32S3.SDMMC.Status := ESP32S3.SDMMC.No_Card;
      Probe  : ESP32S3.SDMMC.Block;
   begin
      --  OEM mount sequence: the GPIO5 gate HIGH for 80 ms, then LOW with
      --  120 ms to settle.  Retry both initialisation AND a block-0 read: a
      --  card can identify while its data path is still settling.
      ESP32S3.GPIO.Configure (Gate_Pin, ESP32S3.GPIO.Output);
      Ready := False;
      for Attempt in 1 .. 4 loop
         ESP32S3.GPIO.Set (Gate_Pin);
         delay 0.080;
         ESP32S3.GPIO.Clear (Gate_Pin);
         delay 0.120;
         ESP32S3.SDMMC.Setup
           (SD, On => ESP32S3.SDMMC.Slot1, Clk => 41, Cmd => 42, D0 => 40,
            Width => ESP32S3.SDMMC.Width_1, Data_Clock_Hz => 20_000_000);
         ESP32S3.SDMMC.Initialize (SD, Status);
         if Status = ESP32S3.SDMMC.OK then
            ESP32S3.SDMMC.Read_Block (SD, 0, Probe, Status);
            exit when Status = ESP32S3.SDMMC.OK;
         end if;
      end loop;
      Put_Line ("[card] SD init: " & ESP32S3.SDMMC.Status'Image (Status));
      Ready := Status = ESP32S3.SDMMC.OK;
      Ok := Ready;
   end Initialize;

end Card;
