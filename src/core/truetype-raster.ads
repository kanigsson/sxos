with Interfaces; use Interfaces;

--  Scanline rasteriser: a Truetype.Outline -> a 16-level coverage bitmap, in
--  exactly the layout the generated atlases use, so the two paths are
--  interchangeable at the pixel level.
--
--  NO HINTING.  Truetype ignores the hinting bytecode, so stems do not snap to
--  the pixel grid.  This package oversamples vertically by Supersample and
--  computes exact analytic coverage horizontally, which removes sampling noise
--  and costs nothing here (a whole page is milliseconds against an e-paper
--  refresh measured in seconds).
--
--  Supersampling does NOT, however, recover what hinting gives you, and it is
--  worth being precise about that because the two are easy to conflate:
--  oversampling makes the coverage ACCURATE, while hinting makes stems
--  GRID-ALIGNED.  An accurate half-covered stem is still two rows of grey where
--  the hinted one is a single solid row.  Measured against the shipped atlas on
--  a line of Korean text (hangul_epd's raster_check):
--
--            solid pixels (>=14/15)   mid greys (4..11)
--    26 px   hinted 63%  unhinted 38%      17%  vs  43%   Nanum Gothic
--    44 px   hinted 55%  unhinted 51%      35%  vs  36%
--    26 px   hinted 36%  unhinted 23%      36%  vs  51%   Nanum Myeongjo
--    44 px   hinted 52%  unhinted 45%      28%  vs  38%
--
--  For the SANS the gap is a small-text problem and has all but closed by 44 px.
--  For the SERIF it is smaller at 26 px but does NOT close: a serif's hairlines
--  are sub-pixel at both sizes, so hinting has less to give at the small end and
--  still something to give at the large one.  Either way Gain below buys most of
--  it back for one multiply.
--
--  Filling is the nonzero winding rule, as TrueType specifies (contours run
--  clockwise for outer, counter-clockwise for holes; overlapping contours are
--  common and must not cancel).
--
--  TARGET-READY on the same terms as Truetype: no heap, no exceptions, no I/O;
--  the caller owns the coverage buffer and every failure is an Ok flag.

package Truetype.Raster
  with SPARK_Mode => On
is

   --  Coverage is 0 .. 15, one byte per pixel, row-major -- the same 16 levels
   --  the T5 spikes' 4 bpp panel displays; Text_Raster thresholds it to 1 bpp.
   type Coverage_Array is array (Natural range <>) of Unsigned_8;

   --  Bound on a rendered glyph.  The Nanum faces' widest glyphs are about 1.1 em,
   --  so this covers sizes past 200 px.
   Max_Size : constant := 256;

   --  Render glyph G at Pixel_Size pixels per em.
   --
   --  The outputs are the atlas's own metric convention, so a rendered glyph can
   --  be handed straight to the same blitter as a generated one:
   --    W, H     the coverage bitmap's extent (0 x 0 for a blank glyph)
   --    X_Off    left bearing: pixels RIGHT of the pen to the bitmap's left edge
   --    Y_Off    pixels DOWN from the baseline to the bitmap's top edge
   --             (negative for the usual glyph, which sits above the baseline)
   --    Adv      pen advance in whole pixels
   --  Cov must hold at least W * H bytes; Ok is False if it does not, if the
   --  glyph exceeds Max_Size, or if the outline could not be decoded.
   --
   --  Gain is stem darkening in sixteenths: coverage is scaled by Gain / 16 and
   --  clamped, so 16 is neutral.  It compensates for the missing grid fit by
   --  pushing partially-covered stems toward solid.  It is a blunt instrument --
   --  it thickens everything, not just stems.
   --
   --  This layer takes it as given and does not choose it: picking a value is
   --  Text_Raster.Gain_For's job, which ramps it down with the type size.  Note
   --  that the right value depends on the FACE as well, which that ramp does not
   --  yet model -- the table above matched at gain 24 (26 px) and 16 (44 px) for
   --  the sans but 19 and 18 for the serif.  Not yet re-measured for Latin faces.
   procedure Render
     (F           : Font;
      G           : Natural;
      Pixel_Size  : Positive;
      W, H        : out Natural;
      X_Off       : out Integer;
      Y_Off       : out Integer;
      Adv         : out Natural;
      Cov         : out Coverage_Array;
      Ok          : out Boolean;
      Supersample : Positive := 4;
      Gain        : Positive := 16);

   --  Pen advance of glyph G at Pixel_Size, in whole pixels.  The same value
   --  Render reports, without rasterising anything -- for measuring a line.
   function Advance_Px
     (F : Font; G : Natural; Pixel_Size : Positive) return Natural;

   --  High-water mark of the internal edge list since start-up.  The list is
   --  the package's one large static buffer, so this is what to measure before
   --  sizing it for a real build.
   function Peak_Edges return Natural;
   function Edge_Capacity return Natural;

end Truetype.Raster;
