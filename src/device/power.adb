with Ada.Real_Time; use Ada.Real_Time;
with Interfaces;    use Interfaces;

with ESP32S3.GPIO;
with ESP32S3.Log; use ESP32S3.Log;
with ESP32S3.RTC;
with ESP32S3.RTC_IO;
with ESP32S3_Registers;
with ESP32S3_Registers.RTC_CNTL;
with ESP32S3_Registers.RTC_IO;

package body Power is
   use type ESP32S3.RTC.Wake_Cause;
   use type ESP32S3_Registers.UInt32;

   Button_Pin : constant ESP32S3.GPIO.Pin_Id := 3;   --  active-low

   Rail_Pin      : constant ESP32S3.GPIO.Pin_Id := 1;
   Touch_Pin     : constant ESP32S3.GPIO.Pin_Id := 2;   --  active-low enable
   Card_Pin      : constant ESP32S3.GPIO.Pin_Id := 5;   --  active-low enable
   Panel_Rst_Pin : constant ESP32S3.GPIO.Pin_Id := 14;
   Cool_Pin      : constant ESP32S3.GPIO.Pin_Id := 8;   --  frontlight
   Warm_Pin      : constant ESP32S3.GPIO.Pin_Id := 9;

   Held : constant array (1 .. 6) of ESP32S3.GPIO.Pin_Id :=
     (Rail_Pin, Touch_Pin, Card_Pin, Panel_Rst_Pin, Cool_Pin, Warm_Pin);

   --  RTC slow memory words: a resume in progress; the off mark.  (Words
   --  1 and 2 held the book to resume, before it moved to the store.)
   Resume_Mark_Word : constant ESP32S3.RTC.Word_Index := 0;
   Off_Mark_Word    : constant ESP32S3.RTC.Word_Index := 3;
   Resume_Mark      : constant Unsigned_32 := 16#5245_534D#;  --  "RESM"
   Off_Mark         : constant Unsigned_32 := 16#4F46_4621#;  --  "OFF!"

   --  The RTC_IO pad registers (GPIO n at TOUCH_PAD0 + 4 n): the sleep puts
   --  the button's pad under RTC control; a wake hands it back.
   type Pad_Array is array (Natural range 0 .. 21) of ESP32S3_Registers.UInt32
     with Volatile;
   Pads : Pad_Array
     with Volatile, Import,
          Address => ESP32S3_Registers.RTC_IO.RTC_IO_Periph.TOUCH_PAD0'Address;
   RTC_Mux : constant ESP32S3_Registers.UInt32 := 2**19;

   Wake : ESP32S3.RTC.Wake_Cause := ESP32S3.RTC.Power_On;
   Was_Off : Boolean := False;

   procedure Deep_Sleep
     with No_Return;

   function Button_Down return Boolean is
     (not ESP32S3.GPIO.Read (Button_Pin));

   --  Whether the button stays down until Power_On_Hold after Start; a
   --  release of 30 ms ends the wait.
   function Held_From (Start : Time) return Boolean is
      Up : Natural := 0;
   begin
      while Clock - Start < To_Time_Span (Power_On_Hold) loop
         Up := (if Button_Down then 0 else Up + 1);
         if Up >= 3 then
            return False;
         end if;
         delay until Clock + Milliseconds (10);
      end loop;
      return True;
   end Held_From;

   procedure Initialize is
      Start : constant Time := Clock;
   begin
      Wake := ESP32S3.RTC.Last_Wake;
      if Wake /= ESP32S3.RTC.Power_On then
         ESP32S3.RTC.Disable_Super_Watchdog;
      end if;
      Pads (Natural (Button_Pin)) := Pads (Natural (Button_Pin)) and not RTC_Mux;
      ESP32S3.GPIO.Configure
        (Button_Pin, ESP32S3.GPIO.Input, ESP32S3.GPIO.Pull_Up);
      Was_Off := Wake = ESP32S3.RTC.Deep_Sleep_GPIO
        and then ESP32S3.RTC.Read (Off_Mark_Word) = Off_Mark;
      if Was_Off then
         --  The pads are still held as the power-off left them.
         if not Held_From (Start) then
            Deep_Sleep;
         end if;
         ESP32S3.RTC.Write (Off_Mark_Word, 0);
      end if;
      for P of Held loop
         ESP32S3.RTC_IO.Release (P);
      end loop;
      Put_Line ("[power] boot: " & Wake'Image
                & (if Was_Off then ", turned on" else ""));
   end Initialize;

   --  After a power-on reset the word holds whatever the RAM came up
   --  with; a match with the 32-bit mark by chance costs one resume.
   function Resume_Safe return Boolean is
     (ESP32S3.RTC.Read (Resume_Mark_Word) /= Resume_Mark);

   procedure Begin_Resume is
   begin
      ESP32S3.RTC.Write (Resume_Mark_Word, Resume_Mark);
   end Begin_Resume;

   procedure End_Resume is
   begin
      ESP32S3.RTC.Write (Resume_Mark_Word, 0);
   end End_Resume;

   --  Drive Pin to Level and latch it through the sleep.
   procedure Hold (Pin : ESP32S3.GPIO.Pin_Id; Level : Boolean) is
   begin
      ESP32S3.GPIO.Configure (Pin, ESP32S3.GPIO.Output);
      ESP32S3.GPIO.Write (Pin, Level);
      ESP32S3.RTC_IO.Hold (Pin);
   end Hold;

   procedure Sleep (Off : Boolean := False) is
   begin
      ESP32S3.RTC.Write (Off_Mark_Word, (if Off then Off_Mark else 0));
      Hold (Rail_Pin, True);
      Hold (Touch_Pin, True);
      Hold (Card_Pin, True);
      Hold (Panel_Rst_Pin, True);
      Hold (Cool_Pin, False);
      Hold (Warm_Pin, False);
      Put_Line (if Off then "[power] off; a long press turns on"
                else "[power] deep sleep; the power button wakes");
      Deep_Sleep;
   end Sleep;

   --  With the pads held: wait for the button's release, then deep-sleep
   --  until it is pressed.
   procedure Deep_Sleep is
      Released : Natural := 0;
   begin
      --  The wake is on the button's LOW level: sleeping while it is still
      --  down would wake at once.  Wait for 100 ms of it being up.
      while Released < 5 loop
         delay until Clock + Milliseconds (20);
         Released := (if Button_Down then 0 else Released + 1);
      end loop;

      ESP32S3.RTC_IO.Enable_RTC_Input (Button_Pin);
      ESP32S3.RTC_IO.Set_Pull (Button_Pin, ESP32S3.RTC_IO.Up);
      delay until Clock + Milliseconds (20);   --  let the log drain

      ESP32S3.RTC.Deep_Sleep_Until (Button_Pin, High => False);

      --  Only reached when the sleep was rejected.
      Put ("[power] deep sleep rejected, cause");
      Put (ESP32S3.RTC.Raw_Reject_Cause);
      Put_Line ("; restarting");
      delay until Clock + Milliseconds (100);
      for P of Held loop
         ESP32S3.RTC_IO.Release (P);
      end loop;
      loop
         ESP32S3_Registers.RTC_CNTL.RTC_CNTL_Periph.OPTIONS0.SW_SYS_RST := True;
      end loop;
   end Deep_Sleep;

end Power;
