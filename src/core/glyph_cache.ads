with Mono_Frame;
with Truetype;

--  Rendered glyphs, kept as 1 bpp bitmaps (or 2 bpp for grey text) so that
--  each glyph of each size is rasterised from its outline once rather than
--  every time it is drawn.
--  A page of text repeats the same few dozen glyphs, and rasterising one is
--  far dearer than copying its bits (the Library, drawn without a cache,
--  took 110 ms on the device for some 300 glyphs).
--
--  Entries are keyed by face, glyph, size, gain and depth.  The cache holds two
--  faces (the interface's and the reading face); a third one, or a full
--  pool, drops everything.  The pool and the table are on
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

   --  Grey text: coverage (0 .. 15) below Light_Min is white, from
   --  Light_Min light grey, from Dark_Min dark grey, from Black_Min black.
   Light_Min : constant := 3;
   Dark_Min  : constant := 7;
   Black_Min : constant := 12;

   --  Draw glyph G in those four levels: every pixel that is not white is
   --  set black in Fr, and the grey ones are marked in Masks.  Adv is the
   --  pen advance.  Kept apart from the 1 bpp glyphs of Draw.
   procedure Draw_Grey
     (Fr       : in out Mono_Frame.Frame;
      Masks    : in out Mono_Frame.Grey_Masks;
      F        : Truetype.Font;
      G        : Natural;
      Size     : Positive;
      Gain     : Positive;
      X        : Integer;
      Baseline : Integer;
      Adv      : out Natural)
     with Global => (In_Out => State);

   --  Drop every glyph.  Call before freeing a face's data: a new face
   --  loaded at the same address must not find the old one's glyphs.
   procedure Drop
     with Global => (In_Out => State);

end Glyph_Cache;
