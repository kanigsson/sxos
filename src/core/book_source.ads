with Interfaces;

with Bytes;
with Fat32;
with Opf;
with Shelf;
with Toc;
with Xhtml_Text;
with Xml_Scan;

--  Open a book from /Books and hand out its text one chapter at a time.
--
--  EPUB: only the ZIP central directory and the package document (OPF)
--  stay in memory; each chapter is read, inflated, checked against its
--  CRC and converted to text when it is loaded, so a book's size is
--  bounded only by its largest chapter.  TXT: the file is read and
--  normalised whole, then served in sections of about Section_Size bytes.
--
--  Text is in the form Xhtml_Text and Plain_Text produce: UTF-8 paragraphs
--  separated by LF.  Not SPARK: it allocates its buffers on the heap (in
--  PSRAM on the device) and reuses them from chapter to chapter.
generic
   with package FS is new Fat32 (<>);
   Books_Folder : String;
package Book_Source is

   type Status is
     (OK,
      Not_Found,     --  no such file, or an archive member is missing
      Read_Error,    --  the card failed
      Not_A_Book,    --  not a ZIP / no container.xml / no OPF / empty spine
      Unsupported,   --  a compression method other than stored or deflate
      Bad_Data,      --  corrupt compressed data or a CRC mismatch
      Too_Big);      --  a chapter or TXT file over the limits below

   --  Uncompressed size of one EPUB chapter's XHTML; the loader needs
   --  about 2.5 times this at once.
   Max_Chapter : constant := 2 * 1024 * 1024;
   --  A whole .txt file.
   Max_Text_File : constant := 3 * 1024 * 1024;
   --  Target size of the sections a .txt file is served in.
   Section_Size : constant := 64 * 1024;

   --  Anchors (element ids) recorded per EPUB chapter; later ones are
   --  not found.
   Max_Anchors : constant := 4096;

   type String_Access is access String;
   type Line_Array_Access is access Toc.Line_Array;

   type Book is limited private;

   --  Open Books_Folder/Name, closing whatever B had open.
   procedure Open
     (V      : in out FS.Volume;
      Name   : String;
      B      : in out Book;
      Result : out Status);

   procedure Close (B : in out Book);

   function Chapter_Count (B : Book) return Natural;

   --  The book's language as its metadata gives it (an EPUB's
   --  <dc:language>, e.g. "de" or "en-US"); empty if unknown, as for TXT.
   function Language (B : Book) return String;

   --  Load chapter I's text; it is Text (B) (1 .. Text_Last (B)) until the
   --  next Load or Close.
   procedure Load
     (V      : in out FS.Volume;
      B      : in out Book;
      I      : Positive;
      Result : out Status)
     with Pre => I <= Chapter_Count (B);

   function Text (B : Book) return String_Access;
   function Text_Last (B : Book) return Natural;

   --  Where the element with id Hash (Xhtml_Text.Id_Hash) starts in the
   --  loaded chapter's text; 0 if the chapter has no such anchor.
   function Anchor_Offset
     (B : Book; Hash : Interfaces.Unsigned_32) return Natural;

   --  The table of contents.  Only EPUBs have one: a TXT file's sections
   --  are arbitrary cuts.
   function Has_Contents (B : Book) return Boolean;

   --  Read the table of contents, unless it is already in memory: the
   --  nav document's, or the NCX's if that gives none (see Toc), each
   --  entry's target resolved to a chapter and an anchor.  Entries whose file is not a chapter are
   --  left out.  A book with no usable one gets an entry per chapter
   --  ("Chapter N").  Uses the member buffer, not the chapter's text.
   procedure Load_Contents (V : in out FS.Volume; B : in out Book)
     with Pre => Has_Contents (B);

   --  Entries I in 1 .. Contents_Count (B) (0 before Load_Contents):
   --  Contents_Lines (B) (I), with labels in Contents_Labels (B).
   function Contents_Count (B : Book) return Natural;
   function Contents_Lines (B : Book) return Line_Array_Access;
   function Contents_Labels (B : Book) return String_Access;

   --  Where entry I leads: a chapter, and perhaps an anchor in it.
   type Target is record
      Chapter    : Positive := 1;
      Has_Anchor : Boolean := False;
      Anchor     : Interfaces.Unsigned_32 := 0;
   end record;

   function Contents_Target (B : Book; I : Positive) return Target
     with Pre => I <= Contents_Count (B);

private
   type Span_Array_Access is access Opf.Span_Array;
   type Index_Array is array (Positive range <>) of Positive;
   type Index_Array_Access is access Index_Array;
   type Anchor_Array_Access is access Xhtml_Text.Anchor_Array;
   type Target_Array is array (Positive range <>) of Target;
   type Target_Array_Access is access Target_Array;

   type Book is limited record
      Format   : Shelf.Book_Format := Shelf.Unknown;
      File     : FS.File;
      Chapters : Natural := 0;

      --  EPUB: the central directory, the OPF's path and text, and the
      --  spine as spans of hrefs into that text.
      Dir      : Bytes.Byte_Array_Access;
      Opf_Path : String_Access;
      Opf_Doc  : String_Access;
      Spine    : Span_Array_Access;
      Lang     : Xml_Scan.Span;   --  in Opf_Doc
      --  The nav document's and the NCX's hrefs, in Opf_Doc (empty if
      --  none).
      Nav_Href : Xml_Scan.Span;
      Ncx_Href : Xml_Scan.Span;

      --  The loaded chapter's anchors.
      Anchors  : Anchor_Array_Access;
      Anchor_Count : Natural := 0;

      --  The table of contents, once loaded.
      Lines    : Line_Array_Access;
      Labels   : String_Access;
      Targets  : Target_Array_Access;
      Entries  : Natural := 0;

      --  TXT: the whole normalised text and where each section starts
      --  (Chapters + 1 entries; the last is one past the end).
      Whole    : String_Access;
      Starts   : Index_Array_Access;

      --  Working buffers, grown as needed: a compressed member, the
      --  member inflated, and the current chapter's text.
      Packed   : Bytes.Byte_Array_Access;
      Member   : Bytes.Byte_Array_Access;
      Member_Size : Natural := 0;
      Text     : String_Access;
      Text_Last : Natural := 0;
   end record;

   function Chapter_Count (B : Book) return Natural is (B.Chapters);
   function Language (B : Book) return String is
     (if B.Opf_Doc = null or else not Xml_Scan.Within (B.Opf_Doc.all, B.Lang)
      then "" else Xml_Scan.Text (B.Opf_Doc.all, B.Lang));
   function Text (B : Book) return String_Access is (B.Text);
   function Text_Last (B : Book) return Natural is (B.Text_Last);
   function Has_Contents (B : Book) return Boolean is
     (Shelf."=" (B.Format, Shelf.EPUB) and then B.Chapters > 0);
   function Contents_Count (B : Book) return Natural is (B.Entries);
   function Contents_Lines (B : Book) return Line_Array_Access is (B.Lines);
   function Contents_Labels (B : Book) return String_Access is (B.Labels);
   function Contents_Target (B : Book; I : Positive) return Target is
     (B.Targets (I));
end Book_Source;
