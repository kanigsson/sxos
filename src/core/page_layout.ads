with Text_Metrics;
with Truetype;

--  Setting a chapter's text into pages.
--
--  The text is what Book_Source hands out: UTF-8 paragraphs separated by LF
--  (an empty paragraph is a blank line).  A paragraph's first line is
--  indented and paragraphs are spaced by Para_Gap.  Lines break greedily at
--  spaces, and after a hyphen or dash inside a word; a no-break space
--  (U+00A0) never breaks.  A word wider than the column is cut at a
--  code-point boundary.
--
--  Every line and page is determined by where it starts, so a page is drawn
--  by setting lines from its start offset again, and a chapter's pages are
--  a table of start offsets (Paginate) built without drawing anything.
package Page_Layout
  with SPARK_Mode => On
is
   type Geometry is record
      Size        : Positive := 1;   --  pixels per em
      Col_Width   : Positive := 1;   --  pixels
      Area_Height : Positive := 1;   --  pixels available for lines
      Line_Height : Positive := 1;   --  baseline to baseline
      Ascent      : Natural := 0;    --  top of a line to its baseline
      Indent      : Natural := 0;    --  first line of a paragraph
      Para_Gap    : Natural := 0;    --  extra space after a paragraph
   end record;

   --  The reader's proportions for T's face and size.
   function Make
     (T : Text_Metrics.Table; F : Truetype.Font;
      Col_Width, Area_Height : Positive) return Geometry;

   type Line is record
      First      : Positive := 1;   --  first byte
      Last       : Natural := 0;    --  last byte; Last < First when empty
      Next       : Positive := 1;   --  where the following line starts
      Width      : Natural := 0;    --  pixels, without the indent
      Spaces     : Natural := 0;    --  breakable spaces inside the line
      Indented   : Boolean := False;
      Para_End   : Boolean := False;   --  the paragraph's last line
   end record;

   --  The line starting at From.
   procedure Break_Line
     (T    : Text_Metrics.Table;
      F    : Truetype.Font;
      G    : Geometry;
      Text : String;
      From : Positive;
      L    : out Line)
     with Pre  => Text'First = 1 and then Text'Last < Positive'Last
                  and then From <= Text'Last,
          Post => L.First = From and then L.Next > From
                  and then L.Next <= Text'Last + 1;

   --  Where the page starting at Start ends: the start of the next page, or
   --  Text'Last + 1.  A page always holds at least one line.
   function Page_End
     (T     : Text_Metrics.Table;
      F     : Truetype.Font;
      G     : Geometry;
      Text  : String;
      Start : Positive) return Positive
     with Pre  => Text'First = 1 and then Text'Last < Positive'Last
                  and then Start <= Text'Last,
          Post => Page_End'Result in Start + 1 .. Text'Last + 1;

   type Offset_Array is array (Positive range <>) of Positive;

   --  Starts (1 .. Count) are the chapter's page starts.  Count is 0 for an
   --  empty text.  If Starts is too short, the last page it holds runs to
   --  the end of the text and Complete is False.
   procedure Paginate
     (T        : Text_Metrics.Table;
      F        : Truetype.Font;
      G        : Geometry;
      Text     : String;
      Starts   : out Offset_Array;
      Count    : out Natural;
      Complete : out Boolean)
     with Pre  => Text'First = 1 and then Text'Last < Positive'Last
                  and then Starts'First = 1 and then Starts'Length > 0,
          Post => Count <= Starts'Last;

   --  The page (1 .. Count) that contains byte Offset.
   function Page_Of
     (Starts : Offset_Array; Count : Positive; Offset : Positive)
      return Positive
     with Pre  => Starts'First = 1 and then Count <= Starts'Last,
          Post => Page_Of'Result <= Count;

end Page_Layout;
