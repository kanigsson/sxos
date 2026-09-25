with Interfaces; use Interfaces;
with ESP32S3.GPIO;
with ESP32S3.I2C; use ESP32S3.I2C;
with ESP32S3.Log; use ESP32S3.Log;

--  The CW2017 register map, initialisation sequence and battery profile are
--  taken from the FreeInk SDK (libs/hardware/BatteryMonitor, MIT licence,
--  Copyright (c) 2026 FreeInk), which recovered them from the X4 Pro's OEM
--  firmware.  The gauge reports 0 % until the matching 80-byte profile is
--  resident, so Initialize checks it and uploads it when it differs.
package body Gauge is

   Addr       : constant Slave_Address := 16#63#;
   Charge_Pin : constant ESP32S3.GPIO.Pin_Id := 21;

   Reg_Version   : constant := 16#00#;   --  0xA0 while starting; 0x0D/0x0F running
   Reg_SOC       : constant := 16#04#;   --  integer percent
   Reg_Mode      : constant := 16#08#;
   Reg_SOC_Alert : constant := 16#0B#;   --  bit 7: profile loaded
   Reg_Batinfo   : constant := 16#10#;   --  80 bytes, 0x10 .. 0x5F

   Mode_Normal  : constant := 16#00#;
   Mode_Restart : constant := 16#30#;
   Mode_Default : constant := 16#F0#;
   Update_Flag  : constant := 16#80#;

   Batinfo : constant Byte_Array (0 .. 79) :=
     (16#50#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
      16#aa#, 16#bf#, 16#b5#, 16#b4#, 16#a4#, 16#9c#, 16#eb#, 16#e2#,
      16#df#, 16#e5#, 16#ca#, 16#a0#, 16#8a#, 16#62#, 16#53#, 16#48#,
      16#40#, 16#3a#, 16#32#, 16#b1#, 16#ae#, 16#da#, 16#b5#, 16#ff#,
      16#ff#, 16#ff#, 16#e8#, 16#db#, 16#d9#, 16#d6#, 16#d4#, 16#d2#,
      16#d0#, 16#cb#, 16#c3#, 16#bc#, 16#9e#, 16#87#, 16#7b#, 16#71#,
      16#72#, 16#7c#, 16#8c#, 16#a3#, 16#b7#, 16#c8#, 16#a5#, 16#4f#,
      16#00#, 16#00#, 16#ab#, 16#02#, 16#00#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#00#, 16#64#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#23#);

   Initialized : Boolean := False;

   procedure Read_Reg (Reg : Natural; Value : out Byte; Ok : out Boolean) is
      Bus : Session;
      Rx  : Byte_Array (0 .. 0);
   begin
      Acquire (Bus, I2C0);
      Write_Read (Bus, Addr, (0 => Byte (Reg)), Rx, Ok);
      Release (Bus);
      Value := Rx (0);
   end Read_Reg;

   procedure Write_Reg (Reg : Natural; Value : Byte; Ok : out Boolean) is
      Bus : Session;
   begin
      Acquire (Bus, I2C0);
      Write (Bus, Addr, (Byte (Reg), Value), Ok);
      Release (Bus);
   end Write_Reg;

   function Running (Version : Byte) return Boolean is
     ((Version and 16#FD#) = 16#0D#);

   --  MODE 0xF0 -> 0x30 -> 0x00, 20 ms apart.
   procedure Restart (Ok : out Boolean) is
   begin
      for M of Byte_Array'(Mode_Default, Mode_Restart, Mode_Normal) loop
         Write_Reg (Reg_Mode, M, Ok);
         exit when not Ok;
         delay 0.020;
      end loop;
   end Restart;

   --  Up to ~1 s for the engine to start, then ~3 s for a valid SoC.
   procedure Wait_Ready (Ok : out Boolean) is
      V : Byte;
   begin
      Ok := False;
      for I in 1 .. 50 loop
         Read_Reg (Reg_Version, V, Ok);
         exit when Ok and then Running (V);
         Ok := False;
         delay 0.020;
      end loop;
      if not Ok then
         return;
      end if;
      Ok := False;
      for I in 1 .. 30 loop
         Read_Reg (Reg_SOC, V, Ok);
         exit when Ok and then V <= 100;
         Ok := False;
         delay 0.100;
      end loop;
   end Wait_Ready;

   procedure Ensure_Profile (Ok : out Boolean) is
      Mode, Version, Config, Stored, Soc : Byte;
      Matches : Boolean;
      Restart_Needed : Boolean;
   begin
      Read_Reg (Reg_Mode, Mode, Ok);
      if Ok then Read_Reg (Reg_Version, Version, Ok); end if;
      if Ok then Read_Reg (Reg_SOC_Alert, Config, Ok); end if;
      if not Ok then
         return;
      end if;

      --  An I2C error is kept apart from a real mismatch, so a transient bus
      --  failure never leads to a partial profile rewrite.
      Matches := (Config and Update_Flag) /= 0;
      if Matches then
         for I in Batinfo'Range loop
            Read_Reg (Reg_Batinfo + I, Stored, Ok);
            if not Ok then
               return;
            end if;
            if Stored /= Batinfo (I) then
               Matches := False;
               exit;
            end if;
         end loop;
      end if;

      Restart_Needed := Mode /= Mode_Normal or else not Running (Version);
      if not Matches then
         Put_Line ("[gauge] uploading the X4 Pro battery profile");
         for I in Batinfo'Range loop
            Write_Reg (Reg_Batinfo + I, Batinfo (I), Ok);
            if not Ok then
               return;
            end if;
         end loop;
         Write_Reg (Reg_SOC_Alert, Update_Flag, Ok);
         if not Ok then
            return;
         end if;
         delay 0.020;
         Restart_Needed := True;
      end if;

      if not Restart_Needed then
         Read_Reg (Reg_SOC, Soc, Ok);
         if Ok and then Soc <= 100 then
            return;
         end if;
      end if;
      Restart (Ok);
      if Ok then
         Wait_Ready (Ok);
      end if;
   end Ensure_Profile;

   procedure Initialize is
   begin
      ESP32S3.GPIO.Configure (Charge_Pin, ESP32S3.GPIO.Input);
      Ensure_Profile (Initialized);
      Put_Line ("[gauge] CW2017 " & (if Initialized then "ready" else "not ready"));
   end Initialize;

   function Read return Status_Bar.Battery is
      Mode, Version, Soc : Byte;
      Ok : Boolean;
      B  : Status_Bar.Battery;
   begin
      B.Charging := ESP32S3.GPIO.Read (Charge_Pin);
      if not Initialized then
         Ensure_Profile (Initialized);
      end if;
      if Initialized then
         Read_Reg (Reg_Mode, Mode, Ok);
         if Ok then Read_Reg (Reg_Version, Version, Ok); end if;
         if Ok then Read_Reg (Reg_SOC, Soc, Ok); end if;
         if Ok and then Mode = Mode_Normal and then Running (Version)
           and then Soc <= 100
         then
            B.Known := True;
            B.Level := Natural (Soc);
         else
            Initialized := False;   --  recover on the next Read
         end if;
      end if;
      return B;
   end Read;

end Gauge;
