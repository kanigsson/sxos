--  The reading text of an (X)HTML chapter: paragraphs separated by
--  Paragraph_Break, markup removed, entities decoded, runs of white space
--  collapsed to one space.  Block elements (p, div, headings, list items,
--  ...) and <br> end a paragraph; empty paragraphs are dropped.  The
--  contents of head, script, style and svg are skipped.  CSS is ignored,
--  and so are images.  Soft hyphens (U+00AD) are kept: they are where
--  the layout may hyphenate a word.
package Xhtml_Text
  with SPARK_Mode => On
is
   Paragraph_Break : constant Character := ASCII.LF;

   --  The text is never longer than the markup it came from, so an Output
   --  as long as Input always suffices; a shorter one truncates.
   procedure Convert
     (Input  : String;
      Output : out String;
      Last   : out Natural)
     with Pre  => Output'First = 1 and then Output'Last < Natural'Last,
          Post => Last <= Output'Last;
end Xhtml_Text;
