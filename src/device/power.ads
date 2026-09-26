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
--
--  Off is the same deep sleep with a mark in RTC slow memory: the board
--  has no power latch, so the chip cannot cut its own supply.  A press
--  while off wakes the chip, but Initialize only lets it boot when the
--  button is held for Power_On_Hold; otherwise it goes straight back to
--  sleep without touching the panel.  Turning on is a fresh start (the
--  Library), not a resume.
package Power is

   --  How long the button must be held to turn the reader on, counted
   --  from the start of Initialize.
   Power_On_Hold : constant Duration := 1.0;

   --  Undo the pad holds of the sleep before anything drives those pins,
   --  and set up the power button.  Call first in Main.  If the reader was
   --  off and the button is not held for Power_On_Hold, it does not
   --  return: the reader goes back to being off.
   procedure Initialize;

   function Button_Down return Boolean;

   --  Whether this boot is a wake from sleep by the power button (not
   --  turning on from off).
   function Woke_Up return Boolean;

   --  The book to reopen after a wake (Found False if none, or not a wake).
   --  Cleared by reading it.
   procedure Take_Resume (A, B : out Unsigned_32; Found : out Boolean);

   procedure Set_Resume (A, B : Unsigned_32);
   procedure Clear_Resume;

   --  Wait for the power button to be released, then deep-sleep until it
   --  is pressed (Off: turned on by a long press).  The panel must already
   --  be asleep (X4_Display.Sleep).  Does not return; if the sleep is
   --  rejected, the chip is reset.
   procedure Sleep (Off : Boolean := False)
     with No_Return;

end Power;
