with Truetype;
with UTF8;

--  Glyph ids and pen advances of one face at one pixel size, looked up once
--  and kept in a table, so laying out a chapter costs one array access per
--  character instead of a cmap search.  The table covers the scripts the
--  reader targets (Latin, Greek, Cyrillic and general punctuation); other
--  code points fall back to the font.
--
--  A space-like code point the face lacks (no-break space, thin space, ...)
--  is given the space's glyph, so it keeps its width instead of vanishing.
package Text_Metrics
  with SPARK_Mode => On
is
   type Table is private;

   procedure Prepare (T : out Table; F : Truetype.Font; Size : Positive);

   function Size (T : Table) return Positive;

   --  F must be the font T was prepared from.
   function Glyph
     (T : Table; F : Truetype.Font; C : UTF8.Code_Point) return Natural;
   function Advance
     (T : Table; F : Truetype.Font; C : UTF8.Code_Point) return Natural;

private
   --  The covered ranges, laid end to end in one array.
   Latin_Last : constant := 16#024F#;                   --  up to Latin Ext-B
   Greek_First : constant := 16#0370#;                  --  Greek, Cyrillic
   Greek_Last  : constant := 16#052F#;
   Punct_First : constant := 16#2000#;                  --  General Punctuation
   Punct_Last  : constant := 16#206F#;

   Greek_Base : constant := Latin_Last + 1;
   Punct_Base : constant := Greek_Base + Greek_Last - Greek_First + 1;
   Slots      : constant := Punct_Base + Punct_Last - Punct_First + 1;

   subtype Slot is Natural range 0 .. Slots - 1;

   type Entry_Type is record
      Glyph   : Natural := 0;
      Advance : Natural := 0;
   end record;

   type Entry_Array is array (Slot) of Entry_Type;

   type Table is record
      Size    : Positive := 1;
      Entries : Entry_Array;
   end record;

   function Size (T : Table) return Positive is (T.Size);
end Text_Metrics;
