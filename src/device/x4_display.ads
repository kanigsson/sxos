with Mono_Frame;

--  The X4 Pro e-paper panel (UC8279 on this unit; SSD1677 path kept for other
--  production batches).  Drawing happens in a Mono_Frame; this package only
--  talks to the controller.
package X4_Display is
   --  Raise the peripheral rail, probe the controller and initialise it.
   procedure Initialize;

   --  Put Frame on the glass with one full refresh (seconds, with flashing).
   procedure Show (Frame : Mono_Frame.Frame);
end X4_Display;
