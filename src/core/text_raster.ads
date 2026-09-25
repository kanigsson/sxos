with Mono_Frame;
with Truetype;

--  UTF-8 text onto a Mono_Frame, rasterised on the device from an outline
--  font.  Adapted from the T5 spikes' Text_Raster, which blended 16 grey
--  levels onto a 4 bpp panel; this panel is 1 bpp, so a glyph pixel is inked
--  when its coverage reaches Ink_Threshold and left alone otherwise.
--
--  Coordinates are portrait Mono_Frame coordinates: text runs left to right
--  along increasing X, above a baseline at Y.
--
--  Glyphs are drawn through Glyph_Cache, which rasterises each glyph and
--  size once.  NOT REENTRANT, like the cache and Truetype.Raster.
package Text_Raster
  with SPARK_Mode => On
is
   --  Coverage 0 .. 15 at or above which a pixel is black.  Half-way, with
   --  stem darkening (Gain) already pushing partially covered stems up.
   Ink_Threshold : constant := 8;

   --  Pass as Gain -- the default everywhere below -- to let the size pick
   --  the stem darkening.  An explicit value still overrides it.
   Auto_Gain : constant := 0;

   --  Stem darkening for type at Size, in sixteenths (16 = neutral).  The
   --  ramp was measured for Nanum faces on the T5 (see truetype-raster.ads)
   --  and is not yet re-fitted for 1 bpp Latin text:
   --
   --    26 -> 24,  32 -> 21,  36 -> 19,  38 -> 18,  44 and up -> 16
   function Gain_For (Size : Positive) return Positive is
     (16 + Integer'Max (0, (44 - Size) * 4 / 9))
     with Pre => Size <= 1024;

   --  Vertical metrics at Size, in whole pixels.  Ascent is above the
   --  baseline, Descent below it (positive); Line_Height adds the line gap.
   function Ascent_Px      (F : Truetype.Font; Size : Positive) return Natural;
   function Descent_Px     (F : Truetype.Font; Size : Positive) return Natural;
   function Line_Height_Px (F : Truetype.Font; Size : Positive) return Positive;

   --  Pixel width of the UTF-8 text Str at Size (advances only; nothing is
   --  rasterised).
   function Width (F : Truetype.Font; Size : Positive; Str : String)
     return Natural;

   --  Draw Str with its pen starting at X.  Black => False draws white ink,
   --  for text on a filled bar.
   procedure Draw_Text
     (Fr       : in out Mono_Frame.Frame;
      F        : Truetype.Font;
      Size     : Positive;
      X        : Integer;
      Baseline : Integer;
      Str      : String;
      Black    : Boolean := True;
      Gain     : Natural := Auto_Gain);

   --  Centred between Left and Right (exclusive).
   procedure Draw_Centered
     (Fr          : in out Mono_Frame.Frame;
      F           : Truetype.Font;
      Size        : Positive;
      Left, Right : Integer;
      Baseline    : Integer;
      Str         : String;
      Black       : Boolean := True;
      Gain        : Natural := Auto_Gain);

   --  Ending at X.
   procedure Draw_Right
     (Fr       : in out Mono_Frame.Frame;
      F        : Truetype.Font;
      Size     : Positive;
      X        : Integer;
      Baseline : Integer;
      Str      : String;
      Black    : Boolean := True;
      Gain     : Natural := Auto_Gain);

   --  The longest prefix of Str, cut at a code-point boundary, whose width
   --  is at most Max_W.  Returns its last byte index (Str'First - 1 if not
   --  even the first code point fits).  For shortening a single line, e.g.
   --  a long file name.
   function Fit (F : Truetype.Font; Size : Positive; Str : String;
                 Max_W : Natural) return Natural;

   --  Greedy line breaking, for setting a paragraph into a column of Max_W
   --  pixels.  Starting at byte From, skip any leading spaces and then take the
   --  longest run of whole space-separated words that still measures <= Max_W:
   --
   --    First  first byte of the line
   --    Last   last byte of the line; Last < First means nothing was placed,
   --           which happens only once From is past the end of Str
   --    Next   byte to continue the paragraph from
   --
   --  A single word wider than the column is broken at a code-point boundary
   --  rather than overrunning, and at least one code point is always placed,
   --  so a caller looping on Next always terminates.
   procedure Wrap_Line
     (F     : Truetype.Font;
      Size  : Positive;
      Str   : String;
      From  : Positive;
      Max_W : Natural;
      First : out Positive;
      Last  : out Natural;
      Next  : out Positive);

end Text_Raster;
