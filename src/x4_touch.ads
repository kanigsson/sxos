--  Xteink X4 Pro GT911 capacitive touch digitizer on the shared I2C bus.
package X4_Touch is
   --  Power the touch rail, run the reset/address-select dance, and probe
   --  the controller.  Present is False when no GT911 answers on the bus;
   --  Read_Contact is then a permanent no-op.
   procedure Initialize (Present : out Boolean);

   --  Poll the digitizer.  Contact is True exactly once per touch, on the
   --  press edge; X/Y then carry the first contact's position in the same
   --  portrait 480x800 frame X4_Display draws in (PX 0..479, PY 0..799).
   procedure Read_Contact (X, Y : out Natural; Contact : out Boolean);
end X4_Touch;
