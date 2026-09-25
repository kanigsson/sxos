with Interfaces; use Interfaces;

--  The power button, deep sleep and waking up.
--
--  Deep sleep follows the X4 Pro's stock and CrossPoint firmware: the
--  peripheral rail (GPIO1) is held HIGH, the SD and touch enables (GPIO5,
--  GPIO2, both active-low) are held off, the panel's RESET is held HIGH
--  (the controller is in its own deep sleep, and the image stays on the
--  glass), and the frontlight pads are held LOW.  The power button (GPIO3,
--  active-low) wakes the chip through RTC EXT1; waking is a reset, so Main
--  starts again from the top.
--
--  A book open when the device went to sleep is remembered in RTC slow
--  memory, which survives deep sleep (not a power cut), so the wake can
--  reopen it.
package Power is

   --  Undo the pad holds of the sleep before anything drives those pins,
   --  and set up the power button.  Call first in Main.
   procedure Initialize;

   function Button_Down return Boolean;

   --  Whether this boot is a wake from deep sleep by the power button.
   function Woke_Up return Boolean;

   --  The book to reopen after a wake (Found False if none, or not a wake).
   --  Cleared by reading it.
   procedure Take_Resume (A, B : out Unsigned_32; Found : out Boolean);

   procedure Set_Resume (A, B : Unsigned_32);
   procedure Clear_Resume;

   --  Wait for the power button to be released, then deep-sleep until it
   --  is pressed.  The panel must already be asleep (X4_Display.Sleep).
   --  Does not return; if the sleep is rejected, the chip is reset.
   procedure Sleep
     with No_Return;

end Power;
