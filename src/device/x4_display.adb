with Ada.Real_Time; use Ada.Real_Time;
with Interfaces; use Interfaces;
with System;

with ESP32S3.GPIO;
with ESP32S3.SPI;
with ESP32S3.Log; use ESP32S3.Log;

package body X4_Display is
   --  X4 Pro pinout from the hardware-confirmed FreeInk SDK profile.
   --  GPIO1 is the board's master peripheral rail and must be asserted before
   --  the display is initialized. The X4 Pro panel controller varies by batch;
   --  Probe_Controller reads the live UC81xx version register; this device
   --  reports LUT_VER=0x68 (UC8279).
   SCLK_Pin : constant ESP32S3.GPIO.Pin_Id := 12;
   MOSI_Pin : constant ESP32S3.GPIO.Pin_Id := 11;
   CS_Pin   : constant ESP32S3.GPIO.Pin_Id := 13;
   DC_Pin   : constant ESP32S3.GPIO.Pin_Id := 18;
   RST_Pin  : constant ESP32S3.GPIO.Pin_Id := 14;
   BUSY_Pin : constant ESP32S3.GPIO.Pin_Id := 6;
   Rail_Pin : constant ESP32S3.GPIO.Pin_Id := 1;

   Bytes_Per_Row : constant := Mono_Frame.Bytes_Per_Row;
   Frame_Size    : constant := Mono_Frame.Frame_Size;
   Transfer_Max  : constant := 4_095;

   subtype Byte is Unsigned_8;
   type Rx_Buffer is array (Natural range 0 .. Transfer_Max - 1) of Byte;
   type Probe_Bytes is array (Natural range <>) of Byte;
   type White_Row_Buffer is array (Natural range 0 .. Bytes_Per_Row - 1) of Byte;
   Rx    : aliased Rx_Buffer;
   White_Row : aliased White_Row_Buffer := (others => 16#FF#);
   Controller_Variant : Byte := 16#FF#;

   --  UC8279 gate geometry: 600 gates addressed, the 480 visible ones start
   --  at gate 120.
   Gate_Offset    : constant := 120;
   Visible_Rows   : constant := Mono_Frame.Panel_Height;
   Addressed_Rows : constant := 600;

   --  UC8279 state: whether the charge pumps are on (stock keeps the panel
   --  powered between refreshes and never sends a second PON), whether DTM1
   --  holds the frame on the glass, and the fast updates since the last
   --  GC-waveform refresh.
   Powered      : Boolean := False;
   Old_Valid    : Boolean := False;
   Fast_Streak  : Natural := 0;

   procedure Send (Data : System.Address; Count : Positive) is
      Session : ESP32S3.SPI.Session;
   begin
      ESP32S3.SPI.Acquire
        (Session, ESP32S3.SPI.SPI2, Mode => 0, Clock_Hz => 10_000_000,
         CS_Pin => CS_Pin);
      ESP32S3.SPI.Select_Device (Session, True);
      ESP32S3.SPI.Transfer (Session, Data, Rx'Address, Count);
      ESP32S3.SPI.Select_Device (Session, False);
      ESP32S3.SPI.Release (Session);
   end Send;

   procedure Send_Byte (Value : Byte) is
      Tx : aliased Byte := Value;
   begin
      Send (Tx'Address, 1);
   end Send_Byte;

   procedure Command (Code : Byte) is
   begin
      ESP32S3.GPIO.Clear (DC_Pin);
      Send_Byte (Code);
   end Command;

   procedure Data_Byte (Value : Byte) is
   begin
      ESP32S3.GPIO.Set (DC_Pin);
      Send_Byte (Value);
   end Data_Byte;

   procedure Wait_Ready (Timeout_Ms : Positive := 10_000) is
      Deadline : constant Time := Clock + Milliseconds (Timeout_Ms);
   begin
      --  SSD1677 BUSY is active-high while the controller is working.
      while ESP32S3.GPIO.Read (BUSY_Pin) loop
         if Clock >= Deadline then
            return;
         end if;
         delay until Clock + Milliseconds (10);
      end loop;
   end Wait_Ready;

   procedure Shift_Out (Value : Byte) is
   begin
      for Bit in reverse 0 .. 7 loop
         ESP32S3.GPIO.Write
           (MOSI_Pin, (Value and Shift_Left (Byte'(1), Bit)) /= 0);
         delay until Clock + Microseconds (1);
         ESP32S3.GPIO.Set (SCLK_Pin);
         delay until Clock + Microseconds (1);
         ESP32S3.GPIO.Clear (SCLK_Pin);
      end loop;
   end Shift_Out;

   function Shift_In return Byte is
      Value : Byte := 0;
   begin
      for Bit in 1 .. 8 loop
         delay until Clock + Microseconds (1);
         Value := Shift_Left (Value, 1);
         if ESP32S3.GPIO.Read (MOSI_Pin) then
            Value := Value or 1;
         end if;
         ESP32S3.GPIO.Set (SCLK_Pin);
         delay until Clock + Microseconds (1);
         ESP32S3.GPIO.Clear (SCLK_Pin);
      end loop;
      return Value;
   end Shift_In;

   procedure Read_Register (Code : Byte; Result : out Probe_Bytes) is
   begin
      ESP32S3.GPIO.Configure (MOSI_Pin, ESP32S3.GPIO.Output);
      ESP32S3.GPIO.Clear (CS_Pin);
      ESP32S3.GPIO.Clear (DC_Pin);
      Shift_Out (Code);
      ESP32S3.GPIO.Set (DC_Pin);
      ESP32S3.GPIO.Configure (MOSI_Pin, ESP32S3.GPIO.Input, ESP32S3.GPIO.Pull_Up);
      for I in Result'Range loop
         Result (I) := Shift_In;
      end loop;
      ESP32S3.GPIO.Set (CS_Pin);
      ESP32S3.GPIO.Configure (MOSI_Pin, ESP32S3.GPIO.Output);
   end Read_Register;

   function Probe_Controller return Byte is
      Status  : Probe_Bytes (0 .. 0);
      Version : Probe_Bytes (0 .. 4);
   begin
      --  UC8179/UC8279 share the UC81xx read registers 0x71/0x70; an SSD1677
      --  has no response and the pulled-up MOSI line reads all ones.
      ESP32S3.GPIO.Set (CS_Pin);
      ESP32S3.GPIO.Clear (SCLK_Pin);
      ESP32S3.GPIO.Clear (DC_Pin);
      ESP32S3.GPIO.Set (RST_Pin);
      delay until Clock + Milliseconds (2);
      ESP32S3.GPIO.Clear (RST_Pin);
      delay until Clock + Milliseconds (50);
      ESP32S3.GPIO.Set (RST_Pin);
      delay until Clock + Milliseconds (30);
      Read_Register (16#71#, Status);
      Read_Register (16#70#, Version);
      Put ("[x4] panel probe FLG=0x");
      Put_Hex (Unsigned_32 (Status (0)), 2);
      Put (" VER=");
      for I in 0 .. 4 loop
         Put_Hex (Unsigned_32 (Version (I)), 2);
         if I < 4 then
            Put (" ");
         end if;
      end loop;
      Put (" BUSY=");
      Put_Line (if ESP32S3.GPIO.Read (BUSY_Pin) then "high" else "low");
      return Version (2);
   end Probe_Controller;

   procedure Send_Selected (S : ESP32S3.SPI.Session; Data : System.Address; Count : Positive) is
   begin
      ESP32S3.SPI.Transfer (S, Data, Rx'Address, Count);
   end Send_Selected;

   --  Stream a 1 bpp frame into a UC8279 RAM plane (DTM1 = old, DTM2 = new):
   --  the panel scans 600 gates with the 480 visible ones starting at 120, so
   --  the frame is framed by white padding rows.  Invert sends the complement
   --  of the frame (the old plane of a Clean refresh).  CS stays asserted
   --  across the whole plane, as the OEM driver does.
   procedure Stream_Plane
     (Code : Byte; Frame : Mono_Frame.Frame; Invert : Boolean := False)
   is
      Session : ESP32S3.SPI.Session;
      Offset  : Natural := 0;
      Row     : aliased White_Row_Buffer;
   begin
      Command (Code);
      ESP32S3.GPIO.Set (DC_Pin);
      ESP32S3.SPI.Acquire
        (Session, ESP32S3.SPI.SPI2, Mode => 0, Clock_Hz => 10_000_000,
         CS_Pin => CS_Pin);
      ESP32S3.SPI.Select_Device (Session, True);
      for R in 1 .. Gate_Offset loop
         Send_Selected (Session, White_Row'Address, Bytes_Per_Row);
      end loop;
      if Invert then
         while Offset < Frame_Size loop
            for I in Row'Range loop
               Row (I) := not Frame (Offset + I);
            end loop;
            Send_Selected (Session, Row'Address, Bytes_Per_Row);
            Offset := Offset + Bytes_Per_Row;
         end loop;
      else
         while Offset < Frame_Size loop
            declare
               Count : constant Positive :=
                 Positive'Min (Transfer_Max, Frame_Size - Offset);
            begin
               Send_Selected (Session, Frame (Offset)'Address, Count);
               Offset := Offset + Count;
            end;
         end loop;
      end if;
      --  The visible rows end at the last addressed gate: no trailing padding.
      pragma Assert (Gate_Offset + Visible_Rows = Addressed_Rows);
      ESP32S3.SPI.Select_Device (Session, False);
      ESP32S3.SPI.Release (Session);
   end Stream_Plane;

   --  Fill a RAM plane white over all addressed gates.
   procedure Fill_Plane_White (Code : Byte) is
      Session : ESP32S3.SPI.Session;
   begin
      Command (Code);
      ESP32S3.GPIO.Set (DC_Pin);
      ESP32S3.SPI.Acquire
        (Session, ESP32S3.SPI.SPI2, Mode => 0, Clock_Hz => 10_000_000,
         CS_Pin => CS_Pin);
      ESP32S3.SPI.Select_Device (Session, True);
      for R in 1 .. Addressed_Rows loop
         Send_Selected (Session, White_Row'Address, Bytes_Per_Row);
      end loop;
      ESP32S3.SPI.Select_Device (Session, False);
      ESP32S3.SPI.Release (Session);
   end Fill_Plane_White;

   procedure Wait_UC_Idle (Timeout_Ms : Positive := 15_000) is
      Deadline : constant Time := Clock + Milliseconds (Timeout_Ms);
   begin
      --  UC8279 BUSY_N is low while active and high when idle.
      while not ESP32S3.GPIO.Read (BUSY_Pin) loop
         if Clock >= Deadline then
            Put_Line ("[x4] timeout waiting for UC8279 BUSY_N high");
            return;
         end if;
         delay until Clock + Milliseconds (10);
      end loop;
   end Wait_UC_Idle;

   procedure Initialize_UC8279 is
   begin
      ESP32S3.GPIO.Clear (RST_Pin);
      delay until Clock + Milliseconds (50);
      ESP32S3.GPIO.Set (RST_Pin);
      delay until Clock + Milliseconds (30);

      Command (16#00#); -- panel setting, REG=1 (UC external LUT profile)
      Data_Byte (16#37#);
      Data_Byte (16#4D#);
      Command (16#61#); -- X4 Pro UC8279 addresses 800x600, 480 gates visible
      Data_Byte (16#03#);
      Data_Byte (16#20#);
      Data_Byte (16#02#);
      Data_Byte (16#58#);
      Command (16#65#); -- gate/source start offsets
      Data_Byte (16#00#);
      Data_Byte (16#00#);
      Data_Byte (16#00#);
      Data_Byte (16#00#);
      Command (16#03#); -- power-off sequence setting
      Data_Byte (16#20#);
      Command (16#30#); -- X4 Pro PLL
      Data_Byte (16#0E#);
      Command (16#E1#); -- gate scan
      Data_Byte (16#02#);
      Powered := False;
      Old_Valid := False;
   end Initialize_UC8279;

   --  UC8279 refresh, following the FreeInk SDK's hardware-validated X4 Pro
   --  driver (Uc8279X4Driver: displayStart / startBwRefresh / displayFinish),
   --  which replays the stock firmware's trigger order.
   --
   --  Full and Clean run the OTP GC waveform; they differ in the old plane:
   --  Full starts from white, Clean from the complement of the target so that
   --  every pixel (the white background too) is driven through a transition,
   --  scrubbing parked ghost charge.  Fast is the DU waveform inside a
   --  full-screen partial window (PTIN + PTL: without the window DU scans but
   --  develops nothing), diffing against the old plane, which after every
   --  refresh holds the frame just shown.
   procedure Show_UC8279 (Frame : Mono_Frame.Frame; Kind : Refresh_Kind) is
      Fast       : constant Boolean := Kind = Fast_Update;
      Y_Start    : constant := Gate_Offset;
      Y_End      : constant := Gate_Offset + Visible_Rows - 1;
      X_End      : constant := Mono_Frame.Panel_Width - 1;
      Busy_Start : Time;
   begin
      Stream_Plane (16#13#, Frame);  --  DTM2: new image
      case Kind is
         when Full        => Fill_Plane_White (16#10#);
         when Clean       => Stream_Plane (16#10#, Frame, Invert => True);
         when Fast_Update => null;  --  DTM1 already holds the shown frame
      end case;

      Command (16#50#); -- CDI: 0x97 for GC, 0xD7 for the windowed DU
      Data_Byte (if Fast then 16#D7# else 16#97#);
      Command (16#E0#); -- CCSET
      Data_Byte (16#02#);
      Command (16#E5#); -- forced temperature: selects GC (0x1E) or DU (0x5A)
      Data_Byte (if Fast then 16#5A# else 16#1E#);
      if Fast then
         Command (16#03#); -- PFS, as stock re-sends it for a partial
         Data_Byte (16#20#);
         Command (16#E1#); -- gate scan
         Data_Byte (16#02#);
      end if;

      if not Powered then
         Command (16#04#); -- power on, wait for idle
         Wait_UC_Idle;
         Powered := True;
      end if;

      if Fast then
         Command (16#91#); -- PTIN
         Command (16#90#); -- PTL: the whole visible area, in gate coordinates
         Data_Byte (16#00#);
         Data_Byte (16#00#);
         Data_Byte (Byte (X_End / 256));
         Data_Byte (Byte (X_End mod 256) or 16#07#);
         Data_Byte (Byte (Y_Start / 256));
         Data_Byte (Byte (Y_Start mod 256));
         Data_Byte (Byte (Y_End / 256));
         Data_Byte (Byte (Y_End mod 256));
         Data_Byte (16#01#);
      end if;

      Command (16#00#); -- after PON, re-latch the panel setting with REG=0 (OTP)
      Data_Byte (16#17#);
      Data_Byte (16#4D#);
      Command (16#12#); -- display refresh

      --  The UC8279 asserts BUSY_N low after starting. Wait for that edge,
      --  then wait until it returns high when the waveform is complete.
      Busy_Start := Clock;
      while ESP32S3.GPIO.Read (BUSY_Pin)
        and then Clock < Busy_Start + Milliseconds (100)
      loop
         delay until Clock + Milliseconds (1);
      end loop;
      Wait_UC_Idle;
      if Fast then
         Command (16#92#); -- PTOUT
      end if;

      --  The old plane becomes the frame now on the glass, for the next DU.
      Stream_Plane (16#10#, Frame);
   end Show_UC8279;

   procedure Initialize is
   begin
      --  Power the board peripherals before touching the EPD pins.
      ESP32S3.GPIO.Configure (Rail_Pin, ESP32S3.GPIO.Output);
      ESP32S3.GPIO.Set (Rail_Pin);
      delay until Clock + Milliseconds (10);

      ESP32S3.GPIO.Configure (CS_Pin, ESP32S3.GPIO.Output);
      ESP32S3.GPIO.Configure (DC_Pin, ESP32S3.GPIO.Output);
      ESP32S3.GPIO.Configure (RST_Pin, ESP32S3.GPIO.Output);
      ESP32S3.GPIO.Configure (BUSY_Pin, ESP32S3.GPIO.Input);
      ESP32S3.GPIO.Configure (SCLK_Pin, ESP32S3.GPIO.Output);
      ESP32S3.GPIO.Configure (MOSI_Pin, ESP32S3.GPIO.Output);
      ESP32S3.GPIO.Set (CS_Pin);
      ESP32S3.GPIO.Set (DC_Pin);
      ESP32S3.GPIO.Set (RST_Pin);
      ESP32S3.GPIO.Clear (SCLK_Pin);
      Controller_Variant := Probe_Controller;

      ESP32S3.SPI.Setup (ESP32S3.SPI.SPI2);
      ESP32S3.SPI.Configure_Pins
        (ESP32S3.SPI.SPI2, Sclk => SCLK_Pin, Mosi => MOSI_Pin,
         Miso => ESP32S3.GPIO.No_Pin);

      if Controller_Variant = 16#68# then
         Put_Line ("[x4] using X4 Pro UC8279 LUT_VER=0x68 waveform");
         Initialize_UC8279;
      else
         Put_Line ("[x4] using SSD1677-compatible X4 waveform");
         --  Hardware reset and the X4 Pro SSD1677 production initialization.
         ESP32S3.GPIO.Clear (RST_Pin);
         delay until Clock + Milliseconds (10);
         ESP32S3.GPIO.Set (RST_Pin);
         delay until Clock + Milliseconds (10);

         Command (16#12#); -- software reset
         delay until Clock + Milliseconds (10); -- fixed settle required by X4 Pro
         Wait_Ready;

         Command (16#18#); -- internal temperature sensor
         Data_Byte (16#80#);
         Command (16#0C#); -- SSD1677 booster soft-start
         Data_Byte (16#AE#);
         Data_Byte (16#C7#);
         Data_Byte (16#C3#);
         Data_Byte (16#C0#);
         Data_Byte (16#80#);
         Command (16#01#); -- 480 gate rows, X4 scan direction
         Data_Byte (16#DF#);
         Data_Byte (16#01#);
         Data_Byte (16#02#);
         Command (16#3C#); -- initial border waveform
         Data_Byte (16#80#);

         Command (16#11#); -- X increment, Y decrement
         Data_Byte (16#01#);
         Command (16#44#); -- X RAM address range: 0 .. 799
         Data_Byte (16#00#);
         Data_Byte (16#00#);
         Data_Byte (16#1F#);
         Data_Byte (16#03#);
         Command (16#45#); -- Y RAM address range: 0 .. 479 (gate scan is reversed)
         Data_Byte (16#DF#);
         Data_Byte (16#01#);
         Data_Byte (16#00#);
         Data_Byte (16#00#);
         Command (16#4E#); -- X RAM counter
         Data_Byte (16#00#);
         Data_Byte (16#00#);
         Command (16#4F#); -- Y RAM counter starts at the final gate row
         Data_Byte (16#DF#);
         Data_Byte (16#01#);
      end if;
   end Initialize;

   procedure Show (Frame : Mono_Frame.Frame; Kind : Refresh_Kind := Fast_Update) is
      Offset : Natural := 0;
      Mode   : Refresh_Kind := Kind;
      T0     : constant Time := Clock;
   begin
      if Controller_Variant = 16#68# then
         if Mode = Fast_Update then
            if not Old_Valid then
               Mode := Full;
            elsif Fast_Streak >= Fast_Updates_Per_Clean then
               Mode := Clean;
            end if;
         end if;
         Show_UC8279 (Frame, Mode);
         Old_Valid := True;
         Fast_Streak := (if Mode = Fast_Update then Fast_Streak + 1 else 0);
         Put ("[x4] " & Mode'Image & " refresh in ");
         Put (Integer (To_Duration (Clock - T0) * 1000.0));
         Put_Line (" ms");
         return;
      end if;

      Command (16#24#); -- write the 1-bpp black/white RAM
      ESP32S3.GPIO.Set (DC_Pin);
      while Offset < Frame_Size loop
         declare
            Count : constant Positive := Positive'Min (Transfer_Max, Frame_Size - Offset);
         begin
            Send (Frame (Offset)'Address, Count);
            Offset := Offset + Count;
         end;
      end loop;

      --  X4 Pro stock full B/W activation (plain internal OTP waveform).
      Command (16#21#); -- bypass the red plane
      Data_Byte (16#40#);
      Command (16#3C#);
      Data_Byte (16#C0#);
      Command (16#22#);
      Data_Byte (16#F7#);
      Command (16#20#);
      Wait_Ready (Timeout_Ms => 15_000);
   end Show;
end X4_Display;
