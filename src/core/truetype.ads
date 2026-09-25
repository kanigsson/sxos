with Interfaces; use Interfaces;
with Bytes;

--  Minimal TrueType (sfnt) outline reader -- the parsing half of an ON-DEVICE
--  text renderer.
--
--  Copied from the T5 4.7 spikes (epd_common, originally hangul_epd) and owned
--  by sxos from here on.  The reader loads a .ttf from the SD card's /Fonts
--  folder into PSRAM and hands this package a pointer to it: outlines cost the
--  same at every type size, so the font-size setting needs no extra files.
--
--  SCOPE.  Deliberately the stb_truetype subset: head, maxp, hhea, hmtx, loca,
--  cmap (formats 4 and 12) and glyf, including composite glyphs -- which matters
--  for Hangul, where 79% of syllables are composites of exactly three jamo
--  components.  NO HINTING: fpgm/prep/cvt and per-glyph instructions are
--  ignored, which is what lets the shipped font drop to 1.3 MB in the first
--  place.  Unhinted stems come out uneven at text sizes, so Truetype.Raster
--  supersamples instead of interpreting hinting bytecode; see its spec.
--
--  TARGET-READY.  No heap, no exceptions, no secondary stack, no I/O: outlines
--  land in a caller-owned bounded record and every entry point reports failure
--  through an Ok flag.  All multi-byte reads are
--  big-endian and bounds-checked against the data slice, so a truncated or
--  corrupt font yields Ok => False rather than reading out of range.

package Truetype
  with SPARK_Mode => On
is

   subtype Byte_Array is Bytes.Byte_Array;

   --  The font file, read in place.  On the host this is a mapped/loaded file;
   --  on the target it would be a flash or PSRAM region -- nothing here copies
   --  or mutates it.
   type Data_Ref is access constant Byte_Array;

   type Font is private;

   --  Parse the table directory and locate the tables needed below.  Ok is
   --  False if the data is not an sfnt, a required table is missing, or any
   --  table lies outside the data.
   procedure Open (Data : Data_Ref; F : out Font; Ok : out Boolean);

   --  Every value below is a 16-bit field of the file, and the bounds say so:
   --  a client scaling them by a pixel size can then show its arithmetic
   --  fits.
   function Units_Per_Em (F : Font) return Positive
     with Post => Units_Per_Em'Result <= 65_535;
   function Num_Glyphs   (F : Font) return Natural
     with Post => Num_Glyphs'Result <= 65_535;

   --  Horizontal metrics in font units (scale by Pixel_Size / Units_Per_Em).
   function Ascent  (F : Font) return Integer
     with Post => Ascent'Result in -32_768 .. 32_767;
   function Descent (F : Font) return Integer    --  negative, as in the file
     with Post => Descent'Result in -32_768 .. 32_767;
   function Line_Gap (F : Font) return Integer
     with Post => Line_Gap'Result in -32_768 .. 32_767;

   --  Glyph id for a Unicode code point; 0 (.notdef) if absent.  An id the
   --  cmap names but the font does not have counts as absent.
   function Glyph_Index (F : Font; Code : Unsigned_32) return Natural
     with Post => Glyph_Index'Result = 0
                  or else Glyph_Index'Result < Num_Glyphs (F);

   --  Advance width of glyph G, in font units.
   function Advance (F : Font; G : Natural) return Natural
     with Post => Advance'Result <= 65_535;

   ---------------------------------------------------------------------------
   --  Outlines
   ---------------------------------------------------------------------------

   --  Bounds for the caller-owned outline record.  The largest simple Hangul
   --  glyph in Nanum Gothic has 212 points; a composite is three of those plus
   --  their contours, so these are ~4x headroom.  Get_Outline reports Ok =>
   --  False rather than overrunning them.
   Max_Points   : constant := 1024;
   Max_Contours : constant := 64;

   --  A point coordinate in font units.  A simple glyph's coordinates are
   --  16-bit (Get_Outline rejects a glyph whose deltas leave that range), and
   --  each level of composite nesting adds one 16-bit offset, so six 16-bit
   --  spans bound any decoded point.
   subtype Coord is Integer range -2**18 .. 2**18;

   --  A point of a quadratic contour, in FONT UNITS (y up).  Off-curve points
   --  are Bezier control points; two consecutive off-curve points imply an
   --  on-curve point at their midpoint, which Truetype.Raster reconstructs.
   type Point is record
      X, Y : Coord;
      On   : Boolean;
   end record;

   type Point_Array   is array (Natural range <>) of Point;
   type Contour_Array is array (Natural range <>) of Natural;

   --  A decoded glyph.  Contour I spans points Ends (I - 1) + 1 .. Ends (I)
   --  (contour 0 starts at 0); each contour is closed.  A blank glyph (a space)
   --  decodes Ok with N_Contours = 0.
   type Outline is record
      N_Points   : Natural range 0 .. Max_Points := 0;
      N_Contours : Natural range 0 .. Max_Contours := 0;
      Points     : Point_Array (0 .. Max_Points - 1);
      Ends       : Contour_Array (0 .. Max_Contours - 1);
   end record;

   --  The contour ends of O are strictly increasing and name decoded points,
   --  so every contour is a non-empty run of O.Points (0 .. N_Points - 1).
   function Well_Formed (O : Outline) return Boolean is
     (for all I in 0 .. O.N_Contours - 1 =>
        O.Ends (I) < O.N_Points
        and then (if I > 0 then O.Ends (I - 1) < O.Ends (I)))
   with Ghost;

   --  Decode glyph G into O, resolving composites (recursively, to a bounded
   --  depth).  Ok is False on malformed data or if the glyph needs more points
   --  or contours than the bounds above.  O is well formed either way.
   procedure Get_Outline
     (F  : Font;
      G  : Natural;
      O  : out Outline;
      Ok : out Boolean)
     with Post => Well_Formed (O);

private

   --  Open rejects a file this large or larger, which bounds every offset
   --  into it well inside Natural: an offset plus a handful of 16-bit
   --  quantities read from the file cannot overflow.  256 MB is far past any
   --  font (the shipped face is 1.3 MB) and past the device's PSRAM.
   Max_Data : constant := 2**28;
   subtype Extent is Natural range 0 .. Max_Data;

   subtype U16_Value is Natural range 0 .. 65_535;
   subtype S16_Value is Integer range -32_768 .. 32_767;

   type Table is record
      Offset : Extent := 0;
      Length : Extent := 0;
   end record;

   type Font is record
      Data       : Data_Ref;
      Head, Maxp, Hhea, Hmtx, Loca, Glyf, Cmap : Table;
      --  The chosen cmap SUBTABLE (not the table), and its format.
      Cmap_Sub   : Table;
      Cmap_Fmt   : U16_Value := 0;
      Upem       : U16_Value range 1 .. U16_Value'Last := 1000;
      N_Glyphs   : U16_Value := 0;
      Long_Loca  : Boolean := False;
      N_HMetrics : U16_Value := 0;
      Asc, Desc, Gap : S16_Value := 0;
   end record;

end Truetype;
