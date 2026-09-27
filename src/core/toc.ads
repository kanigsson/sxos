with Xml_Scan; use Xml_Scan;

--  An EPUB's table of contents, from its EPUB 3 navigation document (the
--  links of <nav epub:type="toc">, nested by <ol>) or its EPUB 2 NCX (the
--  <navPoint>s of the <navMap>).  Works on the document's text; spans
--  point into it.  Labels are raw markup (entities, perhaps tags), to be
--  turned into text by Xhtml_Text; hrefs are relative to the document.
package Toc
  with SPARK_Mode => On
is
   --  Deeper entries are shown at this level.
   Max_Level : constant := 8;
   subtype Level_Type is Positive range 1 .. Max_Level;

   type Item is record
      Level : Level_Type := 1;   --  1: top level
      Label : Span;
      Href  : Span;
   end record;
   type Item_Array is array (Positive range <>) of Item;

   --  An entry as shown: its level and its label, the text
   --  Labels (First .. Last) of a buffer that holds all the labels.
   type Line is record
      Level : Level_Type := 1;
      First : Positive := 1;
      Last  : Natural := 0;
   end record;
   type Line_Array is array (Positive range <>) of Line;

   --  An upper bound on the number of entries: the <a> tags of a nav
   --  document, the <content> tags of an NCX.
   function Count_Links (Doc : String; Is_Nav : Boolean) return Natural;

   --  The entries in document order.  In a nav document, the toc nav is
   --  used, or the first nav when none says it is the toc; links with no
   --  href (headings) are left out.
   procedure Read
     (Doc    : String;
      Is_Nav : Boolean;
      Items  : out Item_Array;
      Count  : out Natural)
     with Pre  => Items'First = 1,
          Post => Count <= Items'Length
                  and then (for all K in 1 .. Count
                            => Within (Doc, Items (K).Label)
                               and then Within (Doc, Items (K).Href));
end Toc;
