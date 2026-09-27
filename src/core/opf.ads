with Xml_Scan; use Xml_Scan;

--  EPUB packaging: find the package document (OPF) through
--  META-INF/container.xml, and read its reading order (the spine) as a list
--  of hrefs.  Works on the documents' text; spans point into it.
package Opf
  with SPARK_Mode => On
is
   Container_Path : constant String := "META-INF/container.xml";

   --  The full-path of the first <rootfile> in container.xml (empty if none).
   function Rootfile (Container : String) return Span
     with Post => Within (Container, Rootfile'Result);

   --  The text of the package's first <dc:language>, a BCP 47 tag such as
   --  "en-US" (empty if there is none).
   function Language (Doc : String) return Span
     with Post => Within (Doc, Language'Result);

   --  A manifest entry.  Html is False for media types other than
   --  (X)HTML, e.g. an SVG-only page, which the reader cannot show.  Nav
   --  marks the EPUB 3 navigation document (properties="nav"), Ncx an
   --  EPUB 2 table of contents (media type application/x-dtbncx+xml).
   type Item is record
      Id, Href : Span;
      Html     : Boolean := False;
      Nav      : Boolean := False;
      Ncx      : Boolean := False;
   end record;
   type Item_Array is array (Positive range <>) of Item;
   type Span_Array is array (Positive range <>) of Span;

   --  Number of <item> and <itemref> tags: bounds for the arrays below.
   function Count_Items (Doc : String) return Natural;
   function Count_Itemrefs (Doc : String) return Natural;

   --  The <manifest>'s items, in document order.
   procedure Read_Manifest
     (Doc   : String;
      Items : out Item_Array;
      Count : out Natural)
     with Post => Count <= Items'Length;

   --  The hrefs of the book's tables of contents: the first navigation
   --  document and the first NCX (empty where there is none).
   procedure Toc_Hrefs
     (Items : Item_Array;
      Nav   : out Span;
      Ncx   : out Span);

   --  The hrefs of the spine's (X)HTML items, in reading order.  An idref
   --  with no matching manifest item is skipped.
   procedure Read_Spine
     (Doc   : String;
      Items : Item_Array;
      Spine : out Span_Array;
      Count : out Natural)
     with Post => Count <= Spine'Length;

   --  The archive path of Href as referenced from the document at Base
   --  (an archive path, e.g. "OEBPS/content.opf"): relative to Base's
   --  folder, percent-escapes and "&amp;" decoded, "." and ".." resolved,
   --  any "#fragment" dropped.  Ok is False if Path is too short.
   procedure Resolve
     (Base : String;
      Href : String;
      Path : out String;
      Last : out Natural;
      Ok   : out Boolean)
     with Pre => Path'First = 1 and then Path'Last < Natural'Last;
end Opf;
