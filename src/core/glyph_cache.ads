with Mono_Frame;
with Truetype;

--  Rendered glyphs, kept as 1 bpp bitmaps so that each glyph of each size
--  is rasterised from its outline once rather than every time it is drawn.
--  A page of text repeats the same few dozen glyphs, and rasterising one is
--  far dearer than copying its bits (the Library, drawn without a cache,
--  took 110 ms on the device for some 300 glyphs).
--
--  Entries are keyed by glyph, size and gain; the whole cache is dropped
--  when the font changes or the pool fills.  The pool and the table are on
--  the heap (PSRAM on the device).  Not reentrant, like Truetype.Raster.
package Glyph_Cache
  with SPARK_Mode => On,
       Abstract_State => State,
       Initializes => State
is
   --  Draw glyph G of F at Size with its pen at (X, Baseline): pixels whose
   --  coverage (0 .. 15) reaches Threshold are set to Black.  Adv is the pen
   --  advance.  A glyph that cannot be rendered draws nothing.
   procedure Draw
     (Fr        : in out Mono_Frame.Frame;
      F         : Truetype.Font;
      G         : Natural;
      Size      : Positive;
      Gain      : Positive;
      Threshold : Natural;
      X         : Integer;
      Baseline  : Integer;
      Black     : Boolean;
      Adv       : out Natural)
     with Global => (In_Out => State);

end Glyph_Cache;
