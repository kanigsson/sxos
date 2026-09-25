with Ada.Real_Time; use Ada.Real_Time;
with Interfaces; use Interfaces;
with ESP32S3.GPIO;
with ESP32S3.I2C;
with ESP32S3.Log; use ESP32S3.Log;

package body X4_Touch is
   --  X4 Pro GT911 wiring, hardware-confirmed via the FreeInk SDK X4 Pro
   --  profile: shared I2C0 bus SDA=39 SCL=38 at 400 kHz (also carrying the
   --  RTC at 0x51 and the battery gauge at 0x63), INT=10, RST=4, strap
   --  addresses 0x5D / 0x14.  The digitizer sits behind an ACTIVE-LOW power
   --  rail on GPIO2 (plus the GPIO1 master rail) and self-loads its config
   --  during the reset dance -- no register upload is needed.
   Sda_Pin   : constant ESP32S3.GPIO.Pin_Id := 39;
   Scl_Pin   : constant ESP32S3.GPIO.Pin_Id := 38;
   Int_Pin   : constant ESP32S3.GPIO.Pin_Id := 10;
   Rst_Pin   : constant ESP32S3.GPIO.Pin_Id := 4;
   Power_Pin : constant ESP32S3.GPIO.Pin_Id := 2;
   Rail_Pin  : constant ESP32S3.GPIO.Pin_Id := 1;

   Addr_Main : constant ESP32S3.I2C.Slave_Address := 16#5D#;
   Addr_Alt  : constant ESP32S3.I2C.Slave_Address := 16#14#;

   use ESP32S3.I2C;

   Available : Boolean := False;
   Address   : ESP32S3.I2C.Slave_Address := 0;
   Touching  : Boolean := False;  --  contact edge tracking

   --  GT911 register map; register addresses are 16-bit, high byte first.
   Reg_Status : constant := 16#814E#;  --  bit7 ready, low nibble contacts
   Reg_Points : constant := 16#8150#;  --  8-byte records, X-lo at byte 0

   procedure Reset_Dance (Int_Level : Boolean) is
   begin
      --  The INT level while RST rises selects the strapped I2C address.
      --  The GT911 also self-loads its internal config during this dance;
      --  shortening it below ~100 ms leaves the controller silent.
      ESP32S3.GPIO.Configure (Int_Pin, ESP32S3.GPIO.Output);
      ESP32S3.GPIO.Configure (Rst_Pin, ESP32S3.GPIO.Output);
      ESP32S3.GPIO.Clear (Rst_Pin);
      ESP32S3.GPIO.Write (Int_Pin, Int_Level);
      delay until Clock + Milliseconds (10);
      ESP32S3.GPIO.Set (Rst_Pin);
      delay until Clock + Milliseconds (10);
      ESP32S3.GPIO.Write (Int_Pin, Int_Level);
      delay until Clock + Milliseconds (50);
      ESP32S3.GPIO.Configure (Int_Pin, ESP32S3.GPIO.Input);
      delay until Clock + Milliseconds (50);
   end Reset_Dance;

   function Probe (Addr : ESP32S3.I2C.Slave_Address) return Boolean is
      Bus   : Session;
      Ok    : Boolean;
      Empty : constant Byte_Array (1 .. 0) := (others => 0);
   begin
      Acquire (Bus, I2C0);
      Write (Bus, Addr, Empty, Ok);  --  address-only probe
      Release (Bus);
      return Ok;
   end Probe;

   function Find_Controller return ESP32S3.I2C.Slave_Address is
   begin
      --  INT low as RST rises straps 0x5D, high straps 0x14.  Try the
      --  documented level first, then the alternate dance before giving up.
      Reset_Dance (False);
      if Probe (Addr_Main) then
         return Addr_Main;
      end if;
      if Probe (Addr_Alt) then
         return Addr_Alt;
      end if;
      Reset_Dance (True);
      if Probe (Addr_Main) then
         return Addr_Main;
      end if;
      if Probe (Addr_Alt) then
         return Addr_Alt;
      end if;
      return 0;
   end Find_Controller;

   procedure Initialize (Present : out Boolean) is
   begin
      --  Rails first: the GT911 needs the GPIO1 master rail HIGH and its own
      --  ACTIVE-LOW enable on GPIO2 driven LOW, or it never ACKs.
      ESP32S3.GPIO.Configure (Rail_Pin, ESP32S3.GPIO.Output);
      ESP32S3.GPIO.Set (Rail_Pin);
      ESP32S3.GPIO.Configure (Power_Pin, ESP32S3.GPIO.Output);
      ESP32S3.GPIO.Clear (Power_Pin);
      delay until Clock + Milliseconds (50);

      ESP32S3.I2C.Setup (I2C0, 400_000);
      ESP32S3.I2C.Configure_Pins (I2C0, Scl => Scl_Pin, Sda => Sda_Pin);

      Address := Find_Controller;
      Available := Address /= 0;
      Touching := False;
      Present := Available;
      if Present then
         Put ("[tp] GT911 found at 0x");
         Put_Hex (Unsigned_32 (Address), 2);
         Put_Line ("");
      else
         Put_Line ("[tp] GT911 absent; touch input disabled");
      end if;
   end Initialize;

   procedure Read_Contact (X, Y : out Natural; Contact : out Boolean) is
      Bus       : Session;
      Ok        : Boolean;
      Points_Ok : Boolean;
      Status    : Byte;
      Status_1  : Byte_Array (1 .. 1);
      Record_Bytes : Byte_Array (0 .. 7);
      Contacts : Natural;
   begin
      X := 0;
      Y := 0;
      Contact := False;
      if not Available then
         return;
      end if;

      Acquire (Bus, I2C0);
      Write_Read
        (Bus, Address,
         Tx => (16#81#, 16#4E#),
         Rx => Status_1,
         Success => Ok);
      if not Ok then
         Release (Bus);
         return;  --  transient bus error: keep the previous contact state
      end if;
      Status := Status_1 (1);
      if (Status and 16#80#) = 0 then
         Release (Bus);
         return;  --  no fresh frame
      end if;

      Contacts := Natural (Status and 16#0F#);
      if Contacts > 0 then
         Write_Read
           (Bus, Address,
            Tx => (16#81#, 16#50#),
            Rx => Record_Bytes,
            Success => Points_Ok);
      else
         Points_Ok := False;
      end if;
      --  The GT911 latches its next report only after 0x814E is cleared.
      Write (Bus, Address, (16#81#, 16#4E#, 16#00#), Ok);
      Release (Bus);

      if Contacts = 0 then
         Touching := False;  --  authoritative release frame
         return;
      end if;
      if not Points_Ok then
         return;
      end if;
      if Touching then
         return;  --  continuation of a held contact: no new press edge
      end if;

      --  The X4 Pro digitizer is mounted portrait and reports its short
      --  axis in X (0..480) and long axis in Y (0..800).  Combined with
      --  X4_Display's portrait raster, FreeInk's corner-tap-confirmed
      --  swap/flip chain reduces to using the raw report directly.
      declare
         Raw_X : constant Natural :=
           Natural (Record_Bytes (0)) + 256 * Natural (Record_Bytes (1));
         Raw_Y : constant Natural :=
           Natural (Record_Bytes (2)) + 256 * Natural (Record_Bytes (3));
      begin
         X := Natural'Min (Raw_X, 479);
         Y := Natural'Min (Raw_Y, 799);
      end;
      Touching := True;
      Contact := True;
   end Read_Contact;
end X4_Touch;
