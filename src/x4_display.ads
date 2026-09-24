with Interfaces;

package X4_Display is
   --  Prototype for an 800x480, 1-bpp SPI panel using an SSD1677-like command
   --  set.  Neither the controller nor the GPIO assignments are confirmed yet.
   procedure Initialize;
   procedure Show_Hello;
end X4_Display;
