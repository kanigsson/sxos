with Bytes;

--  The reading text of a .txt book, in the same form as Xhtml_Text's:
--  UTF-8 paragraphs separated by Paragraph_Break, white space collapsed.
--
--  Files that are not valid UTF-8 are read as Windows-1252 (a superset of
--  Latin-1).  Line breaks are interpreted by the file's convention: if it
--  has blank lines and its lines are short (hard-wrapped text, e.g. Project
--  Gutenberg), blank lines separate paragraphs and single line breaks are
--  joined; otherwise every line is a paragraph.
package Plain_Text
  with SPARK_Mode => On
is
   Paragraph_Break : constant Character := ASCII.LF;

   --  An Output length that always suffices for Input.
   function Output_Bound (Input : Bytes.Byte_Array) return Natural;

   procedure Normalize
     (Input  : Bytes.Byte_Array;
      Output : out String;
      Last   : out Natural)
     with Pre  => Output'First = 1
                  and then Output'Last in 0 .. Natural'Last - 1,
          Post => Last <= Output'Last;

   --  Where the section starting at Text (From) should end, for a section
   --  of about Target bytes: the end of the first paragraph that reaches
   --  Target, or failing that within 2 * Target, a space before Target, or
   --  a character boundary.  Long texts are cut into sections so that no
   --  "chapter" is too long to lay out quickly.
   function Section_End
     (Text : String; From : Positive; Target : Positive) return Positive
     with Pre  => From in Text'Range,
          Post => Section_End'Result in From .. Text'Last;
end Plain_Text;
