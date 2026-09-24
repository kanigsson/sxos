with Ada.Real_Time; use Ada.Real_Time;
with Interfaces; use Interfaces;
with System;

with ESP32S3.GPIO;
with ESP32S3.SPI;

package body X4_Display is
   --  PROVISIONAL GPIOs only. Confirm the X4 Pro board revision/pinout before
   --  connecting this driver to hardware or flashing it.
   SCLK_Pin : constant ESP32S3.GPIO.Optional_Pin := 12;
   MOSI_Pin : constant ESP32S3.GPIO.Optional_Pin := 11;
   CS_Pin   : constant ESP32S3.GPIO.Pin_Id := 10;
   DC_Pin   : constant ESP32S3.GPIO.Pin_Id := 9;
   RST_Pin  : constant ESP32S3.GPIO.Pin_Id := 8;
   BUSY_Pin : constant ESP32S3.GPIO.Pin_Id := 7;

   Width       : constant := 800;
   Height      : constant := 480;
   Bytes_Per_Row : constant := Width / 8;
   Frame_Size  : constant := Bytes_Per_Row * Height;
   Transfer_Max : constant := 4_095;

   subtype Byte is Unsigned_8;
   type Framebuffer is array (Natural range 0 .. Frame_Size - 1) of Byte;
   type Rx_Buffer is array (Natural range 0 .. Transfer_Max - 1) of Byte;
   Frame : aliased Framebuffer;
   Rx    : aliased Rx_Buffer;

   procedure Send (Data : System.Address; Count : Positive) is
      Session : ESP32S3.SPI.Session;
   begin
      ESP32S3.SPI.Acquire
        (Session, ESP32S3.SPI.SPI2, Mode => 0, Clock_Hz => 4_000_000,
         CS_Pin => CS_Pin);
      ESP32S3.SPI.Transfer (Session, Data, Rx'Address, Count);
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
      --  SSD1677-family BUSY is commonly high while the controller is working;
      --  verify this polarity for the actual controller before relying on it.
      while ESP32S3.GPIO.Read (BUSY_Pin) loop
         if Clock >= Deadline then
            return;
         end if;
         delay until Clock + Milliseconds (10);
      end loop;
   end Wait_Ready;

   procedure Initialize is
   begin
      ESP32S3.GPIO.Configure (CS_Pin, ESP32S3.GPIO.Output);
      ESP32S3.GPIO.Configure (DC_Pin, ESP32S3.GPIO.Output);
      ESP32S3.GPIO.Configure (RST_Pin, ESP32S3.GPIO.Output);
      ESP32S3.GPIO.Configure (BUSY_Pin, ESP32S3.GPIO.Input);
      ESP32S3.GPIO.Set (CS_Pin);
      ESP32S3.GPIO.Set (DC_Pin);
      ESP32S3.GPIO.Set (RST_Pin);

      ESP32S3.SPI.Setup (ESP32S3.SPI.SPI2);
      ESP32S3.SPI.Configure_Pins
        (ESP32S3.SPI.SPI2, Sclk => SCLK_Pin, Mosi => MOSI_Pin,
         Miso => ESP32S3.GPIO.No_Pin);

      ESP32S3.GPIO.Clear (RST_Pin);
      delay until Clock + Milliseconds (10);
      ESP32S3.GPIO.Set (RST_Pin);
      delay until Clock + Milliseconds (10);
      Wait_Ready;

      --  Minimal SSD1677-style reset and 800x480 geometry setup.  Actual panel
      --  variants often require a panel-specific LUT/power sequence; this is
      --  intentionally a bring-up hypothesis, not a validated panel init.
      Command (16#12#); -- software reset
      Wait_Ready;
      Command (16#01#); -- driver output control: 480 gate rows
      Data_Byte (16#DF#);
      Data_Byte (16#01#);
      Data_Byte (16#00#);
      Command (16#11#); -- data entry: X and Y increment
      Data_Byte (16#03#);
      Command (16#44#); -- RAM X range: 100 bytes
      Data_Byte (16#00#);
      Data_Byte (16#63#);
      Command (16#45#); -- RAM Y range: 480 rows
      Data_Byte (16#00#);
      Data_Byte (16#00#);
      Data_Byte (16#DF#);
      Data_Byte (16#01#);
   end Initialize;

   function Glyph_Row (C : Character; Row : Natural) return String is
      type Rows is array (1 .. 7) of String (1 .. 5);
      H : constant Rows := ("#   #", "#   #", "#####", "#   #", "#   #", "#   #", "#   #");
      E : constant Rows := ("#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####");
      L : constant Rows := ("#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####");
      O : constant Rows := (" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### ");
      Blank : constant String (1 .. 5) := "     ";
   begin
      if Row not in 1 .. 7 then
         return Blank;
      end if;
      case C is
         when 'h' => return H (Row);
         when 'e' => return E (Row);
         when 'l' => return L (Row);
         when 'o' => return O (Row);
         when others => return Blank;
      end case;
   end Glyph_Row;

   procedure Set_Black (X, Y : Natural) is
      Index : constant Natural := Y * Bytes_Per_Row + X / 8;
      Mask  : constant Byte := Shift_Left (Byte'(1), 7 - (X mod 8));
   begin
      Frame (Index) := Frame (Index) and not Mask;
   end Set_Black;

   procedure Render_Hello is
      Text : constant String := "hello";
      X0   : constant Natural := (Width - (Text'Length * 6 - 1)) / 2;
      Y0   : constant Natural := (Height - 7) / 2;
   begin
      Frame := (others => 16#FF#); -- white background for the common 1=white format
      for Letter in Text'Range loop
         for Row in 1 .. 7 loop
            declare
               Bits : constant String := Glyph_Row (Text (Letter), Row);
               Y    : constant Natural := Y0 + Row - 1;
               X    : constant Natural := X0 + (Letter - Text'First) * 6;
            begin
               for Col in Bits'Range loop
                  if Bits (Col) = '#' then
                     Set_Black (X + Col - Bits'First, Y);
                  end if;
               end loop;
            end;
         end loop;
      end loop;
   end Render_Hello;

   procedure Show_Hello is
      Offset : Natural := 0;
   begin
      Render_Hello;

      Command (16#4E#); -- X address counter
      Data_Byte (16#00#);
      Command (16#4F#); -- Y address counter
      Data_Byte (16#00#);
      Data_Byte (16#00#);
      Command (16#24#); -- write monochrome image RAM
      ESP32S3.GPIO.Set (DC_Pin);
      while Offset < Frame_Size loop
         declare
            Count : constant Positive := Positive'Min (Transfer_Max, Frame_Size - Offset);
         begin
            Send (Frame (Offset)'Address, Count);
            Offset := Offset + Count;
         end;
      end loop;

      Command (16#22#); -- display update control
      Data_Byte (16#F7#);
      Command (16#20#); -- activate display update
      Wait_Ready;
   end Show_Hello;
end X4_Display;
