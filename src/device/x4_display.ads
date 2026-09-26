with Mono_Frame;

--  The X4 Pro e-paper panel (UC8279 on this unit; SSD1677 path kept for other
--  production batches).  Drawing happens in a Mono_Frame; this package only
--  talks to the controller.
package X4_Display is
   --  Full:        GC waveform from white; seconds, with flashing.
   --  Clean:       GC waveform from the inverse of the new frame: every pixel
   --                is driven, which clears accumulated ghosting.
   --  Fast_Update: DU waveform diffing against the frame on the glass; no
   --                flashing, but leaves ghosting that builds up.
   type Refresh_Kind is (Full, Clean, Fast_Update);

   --  A Fast_Update becomes a Clean after this many fast updates in a row,
   --  and a Full when nothing is known to be on the glass yet.
   Fast_Updates_Per_Clean : constant := 10;

   --  Raise the peripheral rail, probe the controller and initialise it.
   procedure Initialize;

   --  Put Frame on the glass.  The SSD1677 path always does a full refresh.
   procedure Show (Frame : Mono_Frame.Frame; Kind : Refresh_Kind := Fast_Update);

   --  Put a greyscale screen on the glass (UC8279 only; elsewhere Frame
   --  alone): Frame, where every pixel that is not white is black, goes up
   --  first as Show would put it, then a second refresh with the stock
   --  anti-aliasing waveform (external LUTs) lightens the pixels Masks
   --  marks grey.  With that waveform light and dark grey look the same.
   --  The screen after a grey one goes up through the stock non-flashing
   --  transition waveform instead of a plain fast update, which keeps the
   --  grey edges' charge from building up.
   procedure Show_Grey
     (Frame : Mono_Frame.Frame;
      Masks : Mono_Frame.Grey_Masks;
      Kind  : Refresh_Kind := Fast_Update);

   --  Power the panel down and put the controller into deep sleep; the
   --  image stays on the glass.  Only Initialize (a reset) wakes it.
   procedure Sleep;
end X4_Display;
