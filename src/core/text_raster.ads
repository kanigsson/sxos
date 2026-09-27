with Mono_Frame;
with Truetype;

--  UTF-8 text onto a Mono_Frame, rasterised on the device from an outline
--  font.  Adapted from the T5 spikes' Text_Raster, which blended 16 grey
--  levels onto a 4 bpp panel; this panel is 1 bpp, so a glyph pixel is inked
--  when its coverage reaches Ink_Threshold and left alone otherwise.
--
--  Coordinates are portrait Mono_Frame coordinates: text runs left to right
--  along increasing X, above a baseline at Y.  Adjacent glyphs are kerned
--  (Truetype.Kerning), rounded to whole pixels.
--
--  A character F lacks is measured and drawn from the Fallback face, if
--  that has it (not kerned against its neighbours); else it is skipped.
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
     (if Size >= 44 then 16 else 16 + (44 - Size) * 4 / 9);

   --  Stem darkening for grey text (Glyph_Cache.Draw_Grey): grey levels
   --  carry what thresholding at 1 bpp loses, so less is needed.  Not yet
   --  fitted on the panel.
   function Grey_Gain_For (Size : Positive) return Positive is
     (if Size >= 32 then 16 else 16 + (32 - Size) / 4);

   --  Vertical metrics at Size, in whole pixels.  Ascent is above the
   --  baseline, Descent below it (positive); Line_Height adds the line gap.
   --  The font's metrics are 16-bit, which bounds each at any sensible size.
   function Ascent_Px      (F : Truetype.Font; Size : Positive) return Natural
     with Post => (if Size <= 1024 then Ascent_Px'Result <= 2**27);
   function Descent_Px     (F : Truetype.Font; Size : Positive) return Natural
     with Post => (if Size <= 1024 then Descent_Px'Result <= 2**27);
   function Line_Height_Px (F : Truetype.Font; Size : Positive) return Positive
     with Post => (if Size <= 1024 then Line_Height_Px'Result <= 2**27);

   --  Every entry point below that decodes Str needs Str'Last < Positive'Last,
   --  as UTF8.Next_Code does: the byte after the text must be addressable.

   --  Pixel width of the UTF-8 text Str at Size (advances and kerning;
   --  nothing is rasterised).  Saturates at Natural'Last.
   function Width (F : Truetype.Font; Size : Positive; Str : String)
     return Natural
     with Pre  => Str'Last < Positive'Last,
          Post => (if Str'Length = 0 then Width'Result = 0);

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
      Gain     : Natural := Auto_Gain)
     with Pre => Str'Last < Positive'Last;

   --  Centred between Left and Right (exclusive).
   procedure Draw_Centered
     (Fr          : in out Mono_Frame.Frame;
      F           : Truetype.Font;
      Size        : Positive;
      Left, Right : Integer;
      Baseline    : Integer;
      Str         : String;
      Black       : Boolean := True;
      Gain        : Natural := Auto_Gain)
     with Pre => Str'Last < Positive'Last;

   --  Ending at X.
   procedure Draw_Right
     (Fr       : in out Mono_Frame.Frame;
      F        : Truetype.Font;
      Size     : Positive;
      X        : Integer;
      Baseline : Integer;
      Str      : String;
      Black    : Boolean := True;
      Gain     : Natural := Auto_Gain)
     with Pre => Str'Last < Positive'Last;

   --  The longest prefix of Str, cut at a code-point boundary, whose width
   --  is at most Max_W.  Returns its last byte index (Str'First - 1 if not
   --  even the first code point fits).  For shortening a single line, e.g.
   --  a long file name.  (A null Str whose bounds lie below 1 has no
   --  Str'First - 1 in Natural; it gives 0.)
   function Fit (F : Truetype.Font; Size : Positive; Str : String;
                 Max_W : Natural) return Natural
     with Pre  => Str'Last < Positive'Last,
          Post => (if Str'First >= 1
                   then Fit'Result = Str'First - 1
                        or else Fit'Result in Str'First .. Str'Last
                   else Fit'Result = 0);

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
   --  so a caller looping on Next always terminates.  A From before
   --  Str'First counts as Str'First.
   procedure Wrap_Line
     (F     : Truetype.Font;
      Size  : Positive;
      Str   : String;
      From  : Positive;
      Max_W : Natural;
      First : out Positive;
      Last  : out Natural;
      Next  : out Positive)
     with Pre  => Str'Last < Positive'Last,
          Post => First >= From and then Next >= First
                  and then Last >= First - 1
                  and then (if Last >= First
                            then First >= Str'First and then Last <= Str'Last
                                 and then Next > Last);

end Text_Raster;
