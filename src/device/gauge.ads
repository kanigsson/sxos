with Status_Bar;

--  Battery state of the X4 Pro: a CW2017 fuel gauge at 0x63 on the shared
--  I2C0 bus (with the GT911 touch and the RTC), and the charger's STAT line
--  on GPIO21 (active high while charging).
--
--  X4_Touch.Initialize sets the bus up; call it first.
package Gauge is

   --  Make sure the gauge runs with the X4 Pro's battery profile, uploading
   --  it if needed.  Takes up to a few seconds after a profile upload; a
   --  failure is retried by Read.
   procedure Initialize;

   --  Current level (Known => False when the gauge cannot be read).
   function Read return Status_Bar.Battery;

end Gauge;
