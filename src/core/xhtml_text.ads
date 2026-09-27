--  The reading text of an (X)HTML chapter: paragraphs separated by
--  Paragraph_Break, markup removed, entities decoded, runs of white space
--  collapsed to one space.  Block elements (p, div, headings, list items,
--  ...) and <br> end a paragraph; empty paragraphs are dropped.  The
--  contents of head, script, style and svg are skipped.  CSS is ignored,
--  and so are images.  Soft hyphens (U+00AD) are kept: they are where
--  the layout may hyphenate a word.
with Interfaces;

package Xhtml_Text
  with SPARK_Mode => On
is
   Paragraph_Break : constant Character := ASCII.LF;

   --  An element's id (or an <a>'s name) and where in the text its
   --  content starts: the target of a link "chapter.xhtml#Id".  The id is
   --  kept as a hash (Id_Hash) only.
   type Anchor is record
      Hash   : Interfaces.Unsigned_32 := 0;
      Offset : Positive := 1;
   end record;
   type Anchor_Array is array (Positive range <>) of Anchor;

   --  FNV-1a over the id's bytes.
   function Id_Hash (Id : String) return Interfaces.Unsigned_32;

   --  The text is never longer than the markup it came from, so an Output
   --  as long as Input always suffices; a shorter one truncates.
   procedure Convert
     (Input  : String;
      Output : out String;
      Last   : out Natural)
     with Pre  => Output'First = 1
                  and then Output'Last in 0 .. Natural'Last - 1,
          Post => Last <= Output'Last;

   --  The same, also recording the anchors: Anchors (Anchors'First ..
   --  Anchors'First + Count - 1), in document order.  An anchor's Offset
   --  is the first character of the text after it (skipping the break or
   --  space before that text), at most Last + 1 (Last = 0: 1).  Anchors
   --  past Anchors'Length are dropped.
   procedure Convert
     (Input   : String;
      Output  : out String;
      Last    : out Natural;
      Anchors : out Anchor_Array;
      Count   : out Natural)
     with Pre  => Output'First = 1
                  and then Output'Last in 0 .. Natural'Last - 1,
          Post => Last <= Output'Last and then Count <= Anchors'Length
                  and then (for all K in Anchors'First .. Anchors'First + Count - 1
                            => Anchors (K).Offset <= Last + 1);
end Xhtml_Text;
