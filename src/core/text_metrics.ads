with Interfaces;
with Fallback;
with Truetype;
with Truetype.Identity;
with UTF8;

--  Glyph ids and pen advances of one face at one pixel size, looked up once
--  and kept in a table, so laying out a chapter costs one array access per
--  character instead of a cmap search.  The table covers the scripts the
--  reader targets (Latin, Greek, Cyrillic, general punctuation, and for
--  Korean: CJK symbols and punctuation through the Hangul compatibility
--  jamo, the Hangul syllables and the halfwidth and fullwidth forms); other
--  code points, Hanja among them, fall back to the font.
--
--  A character the face lacks is taken from the Fallback chain (as it was
--  when the table was prepared), glyph and advance; it is not kerned.
--
--  A space-like code point the face lacks (no-break space, thin space, ...)
--  is given the space's glyph, so it keeps its width instead of vanishing.
--  A soft hyphen (U+00AD) has no glyph and no width.
--
--  Pair kerning is tabled too, in whole pixels, for the pairs of visible
--  Basic Latin, Latin-1, Latin Extended-A and General Punctuation (U+2010
--  .. U+2027) characters; other pairs are not kerned.  The table in font
--  units is kept while the face stays the same, so a size change only
--  rescales it.  A Table is large (some 700 KB): allocate it on the heap.
package Text_Metrics
  with SPARK_Mode => On
is
   type Table is private;

   function Size (T : Table) return Positive;

   procedure Prepare (T : in out Table; F : Truetype.Font; Size : Positive)
     with Global => (Fallback.State, Truetype.Identity.Addresses),
          Post   => Text_Metrics.Size (T) = Size;

   --  F must be the font T was prepared from.  The glyph for C (0 for
   --  none), and the face it is in: F, or a fallback face.
   procedure Find
     (T     : Table;
      F     : Truetype.Font;
      C     : UTF8.Code_Point;
      Found : out Truetype.Font;
      G     : out Natural);
   function Advance
     (T : Table; F : Truetype.Font; C : UTF8.Code_Point) return Natural;

   --  No character before: nothing to kern with.
   No_Code : constant UTF8.Code_Point := 0;

   --  The pen adjustment, in pixels, between Left and Right set side by
   --  side (negative: closer).  0 for a pair not tabled.
   function Kern (T : Table; Left, Right : UTF8.Code_Point) return Integer
     with Post => Kern'Result in -128 .. 127;

private
   --  The covered ranges, laid end to end in one array.
   Latin_Last : constant := 16#024F#;                   --  up to Latin Ext-B
   Greek_First : constant := 16#0370#;                  --  Greek, Cyrillic
   Greek_Last  : constant := 16#052F#;
   Punct_First : constant := 16#2000#;                  --  General Punctuation
   Punct_Last  : constant := 16#206F#;
   CJK_First   : constant := 16#3000#;       --  CJK Symbols and Punctuation
   CJK_Last    : constant := 16#318F#;       --  .. Hangul Compatibility Jamo
   Hangul_First : constant := 16#AC00#;      --  Hangul Syllables
   Hangul_Last  : constant := 16#D7A3#;
   Wide_First  : constant := 16#FF00#;       --  Halfwidth and Fullwidth Forms
   Wide_Last   : constant := 16#FFEF#;

   Greek_Base  : constant := Latin_Last + 1;
   Punct_Base  : constant := Greek_Base + Greek_Last - Greek_First + 1;
   CJK_Base    : constant := Punct_Base + Punct_Last - Punct_First + 1;
   Hangul_Base : constant := CJK_Base + CJK_Last - CJK_First + 1;
   Wide_Base   : constant := Hangul_Base + Hangul_Last - Hangul_First + 1;
   Slots       : constant := Wide_Base + Wide_Last - Wide_First + 1;

   subtype Slot is Natural range 0 .. Slots - 1;

   type Entry_Type is record
      Glyph   : Natural := 0;
      Advance : Natural := 0;
      --  0: Glyph is F's; else it is in Backups (Source).
      Source  : Natural range 0 .. Fallback.Max_Faces := 0;
   end record;

   type Face_Array is array (Fallback.Index) of Truetype.Font;

   type Entry_Array is array (Slot) of Entry_Type;

   --  The kerned characters: visible Basic Latin, U+00A1 .. U+017F, and
   --  U+2010 .. U+2027, laid end to end.
   Kern_Latin_1 : constant := 16#A1#;
   Kern_Punct   : constant := 16#2010#;
   Kern_Base_2  : constant := 16#7E# - 16#21# + 1;
   Kern_Base_3  : constant := Kern_Base_2 + 16#17F# - Kern_Latin_1 + 1;
   Kern_Slots   : constant := Kern_Base_3 + 16#2027# - Kern_Punct + 1;

   subtype Kern_Slot is Natural range 0 .. Kern_Slots - 1;
   subtype Kern_Index is Natural range 0 .. Kern_Slots * Kern_Slots - 1;

   type Kern_Px_Array is array (Kern_Index) of Interfaces.Integer_8
     with Default_Component_Value => 0;

   type Table is record
      Size    : Positive := 1;
      Entries : Entry_Array;
      --  The fallback chain when prepared, for what the face lacks.
      Backups   : Face_Array;
      N_Backups : Fallback.Count_Type := 0;
      --  Kerning of the tabled pairs (Left * Kern_Slots + Right): in font
      --  units for Kern_Face, when Kern_Valid, and in pixels at Size.
      Kern_Valid  : Boolean := False;
      Kern_Face   : Truetype.Font;
      Kern_Glyphs : Truetype.Glyph_List (Kern_Slot);
      Kern_Units  : Truetype.Kern_Matrix (Kern_Index);
      Settled     : Truetype.Flag_Matrix (Kern_Index);
      Kern_Px     : Kern_Px_Array;
   end record;

   function Size (T : Table) return Positive is (T.Size);
end Text_Metrics;
