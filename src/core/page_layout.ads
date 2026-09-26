with Hyphenation;
with Text_Metrics;
with Truetype;

--  Setting a chapter's text into pages.
--
--  The text is what Book_Source hands out: UTF-8 paragraphs separated by LF
--  (an empty paragraph is a blank line).  A paragraph's first line is
--  indented and paragraphs are spaced by Para_Gap.  Lines may break at
--  spaces, after a hyphen or dash inside a word, and at a soft hyphen
--  (U+00AD, which is otherwise invisible); a no-break space (U+00A0) never
--  breaks.  With patterns in Hyph, words are hyphenated too, unless they
--  have soft hyphens of their own.  Widths include the kerning of adjacent
--  characters (Text_Metrics.Kern); a space, and the start of a line, break
--  the chain.
--
--  A paragraph is set as a whole (Knuth and Plass, simplified): of all the
--  ways to break it, the one whose lines stretch or shrink their spaces
--  least, with a cost for hyphens and for a loose line next to a tight
--  one.  Hyphenation points are only tried when the paragraph cannot be
--  set well without them.  A paragraph too long for the Workspace, or with
--  a word wider than the column, is set greedily instead (Break_Line), and
--  such a word is cut at a code-point boundary.
--
--  Every page is determined by where it starts: its first paragraph is set
--  again from the paragraph's start, and the page takes the lines from
--  Start on.  So a page is drawn by setting it again (Page_Lines), and a
--  chapter's pages are a table of start offsets (Paginate) built by the
--  same procedure without drawing anything.
package Page_Layout
  with SPARK_Mode => On
is
   --  The largest type size laid out, and a bound on every length in a
   --  Geometry: far beyond any screen, but it keeps sums of a few of them
   --  clear of overflow.  A face whose metrics exceed it is clamped to it.
   Max_Size : constant := 1024;
   Max_Px   : constant := 2**15;

   subtype Px is Natural range 0 .. Max_Px;
   subtype Positive_Px is Px range 1 .. Max_Px;

   type Geometry is record
      Size        : Positive range 1 .. Max_Size := 1;   --  pixels per em
      Col_Width   : Positive_Px := 1;   --  pixels
      Area_Height : Positive_Px := 1;   --  pixels available for lines
      Line_Height : Positive_Px := 1;   --  baseline to baseline
      Ascent      : Px := 0;            --  top of a line to its baseline
      Indent      : Px := 0;            --  first line of a paragraph
      Para_Gap    : Px := 0;            --  extra space after a paragraph
      Hyph        : Hyphenation.Trie_Ref := null;   --  none: no patterns
   end record;

   --  The reader's proportions for T's face and size, without patterns.
   function Make
     (T : Text_Metrics.Table; F : Truetype.Font;
      Col_Width, Area_Height : Positive) return Geometry
     with Pre => Text_Metrics.Size (T) <= Max_Size
                 and then Col_Width <= Max_Px and then Area_Height <= Max_Px;

   --  A + B, or Natural'Last when that overflows.  Widths are sums of font
   --  advances over arbitrary text, so they are added saturating.
   function Add_Sat (A, B : Natural) return Natural is
     (if B <= Natural'Last - A then A + B else Natural'Last);

   --  A moved by a kerning adjustment K, clamped to 0 and saturating.
   function Add_Kern (A : Natural; K : Integer) return Natural is
     (if K >= 0 then Add_Sat (A, K) else Natural'Max (0, A + K));

   type Line is record
      First      : Positive := 1;   --  first byte
      Last       : Natural := 0;    --  last byte; Last < First when empty
      Next       : Positive := 1;   --  where the following line starts
      Width      : Natural := 0;    --  pixels, without the indent: may be
                                    --  more than the column (Shrink_Of)
      Spaces     : Natural := 0;    --  breakable spaces inside the line
      Indented   : Boolean := False;
      Para_End   : Boolean := False;   --  the paragraph's last line
      Hyphen     : Boolean := False;   --  ends in a hyphen not in the text
   end record;

   --  The greedy line starting at From: as many characters as fit.
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
                  and then L.Next <= Text'Last + 1
                  and then L.Last <= Text'Last,
          Always_Terminates;

   --  How far a justified line may move its spaces, per space: stretch
   --  without limit (but at a cost that grows with the cube of the ratio to
   --  Stretch_Of), shrink down to Shrink_Of less than the natural width.
   function Stretch_Of (Space_W : Natural) return Natural is (Space_W / 2);
   function Shrink_Of (Space_W : Natural) return Natural is (Space_W / 3);

   --  The places a paragraph may break, and the cheapest way to reach each
   --  of them.  Page_Layout's own; large (about 400 KB), so the caller
   --  keeps one on the heap.
   Max_Breaks     : constant := 4096;
   Max_Page_Lines : constant := 256;

   type Fitness is (Tight, Decent, Loose, Very_Loose);
   Infinite : constant := 2**62;
   type Demerits is range 0 .. Infinite;
   type Cost_Array is array (Fitness) of Demerits;
   type Index_Array is array (Fitness) of Natural;
   type Fitness_Array is array (Fitness) of Fitness;

   --  A break: the line ending here ends at Last with End_W pixels and
   --  End_Sp spaces of the paragraph before it (its hyphen included), and
   --  the line after it starts at Next, at Start_W and Start_Sp.  A line's
   --  width is its end's End_W less its start's Start_W.
   type Break is record
      Last     : Natural := 0;
      Next     : Positive := 1;
      End_W    : Natural := 0;
      Start_W  : Natural := 0;
      End_Sp   : Natural := 0;
      Start_Sp : Natural := 0;
      Penalty  : Natural := 0;
      Hyphen   : Boolean := False;   --  a hyphen drawn at the break
      Flagged  : Boolean := False;   --  a hyphen, drawn or in the text
      --  The cheapest set of the paragraph up to here, per fitness of the
      --  line ending here, and the break and fitness it comes from.
      Cost     : Cost_Array := (others => Infinite);
      From     : Index_Array := (others => 0);
      From_Fit : Fitness_Array := (others => Decent);
      Succ     : Natural := 0;       --  the chosen line's end
   end record;

   type Break_Array is array (0 .. Max_Breaks) of Break;
   type Line_Array is array (1 .. Max_Page_Lines) of Line;

   type Workspace is record
      Brk        : Break_Array;
      Count      : Natural range 0 .. Max_Breaks := 0;
      Optimal    : Boolean := False;   --  Brk holds the paragraph's set
      Cached     : Boolean := False;   --  Brk is for the text being set
      Para_First : Positive := 1;
      Lines      : Line_Array;
   end record;

   --  W.Lines (1 .. Count) are the lines of the page starting at Start.  A
   --  page always holds at least one line; the last one's Next is where
   --  the next page starts (Text'Last + 1 at the end).
   procedure Page_Lines
     (T     : Text_Metrics.Table;
      F     : Truetype.Font;
      G     : Geometry;
      Text  : String;
      Start : Positive;
      W     : in out Workspace;
      Count : out Positive)
     with Pre  => Text'First = 1 and then Text'Last < Positive'Last
                  and then Start <= Text'Last,
          Post => Count <= Max_Page_Lines
                  and then W.Lines (Count).Next in Start + 1 .. Text'Last + 1;

   type Offset_Array is array (Positive range <>) of Positive;

   --  Starts (1 .. Count) are the chapter's page starts.  Count is 0 for an
   --  empty text.  If Starts is too short, the last page it holds runs to
   --  the end of the text and Complete is False.
   procedure Paginate
     (T        : Text_Metrics.Table;
      F        : Truetype.Font;
      G        : Geometry;
      Text     : String;
      W        : in out Workspace;
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
