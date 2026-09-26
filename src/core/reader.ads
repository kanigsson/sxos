with Book_Source;
with Fat32;
with Hyphen_Loader;
with Mono_Frame;
with Status_Bar;
with Truetype;

--  A reading session: the open book, its current chapter laid out into
--  pages, and the page on the screen.
--
--  Page turns run across chapter boundaries; chapters with no text (a
--  cover image, an empty title page) are skipped.  A chapter that fails to
--  load is one page with the reason on it, so the rest of the book stays
--  reachable.  The position is (chapter, byte offset of the page start):
--  it survives re-laying out the chapter at another size.
--
--  Chapters are hyphenated in their language: the one Language_Guess finds
--  in the chapter's text when it is sure, else the book's metadata, else
--  the last chapter's.  Metadata is often wrong (a German book tagged
--  "en"), which is why the text comes first.
--
--  One session at a time: the state is the package's own, and the page
--  table is on the heap.  Instantiate at library level, not inside a
--  subprogram, to keep that state off the stack.
generic
   with package FS is new Fat32 (<>);
   with package Books is new Book_Source (FS => FS, others => <>);
   with package Hyphens is new Hyphen_Loader (FS => FS, others => <>);
package Reader is

   type Position is record
      Chapter : Natural := 0;    --  0: the start of the book
      Offset  : Positive := 1;   --  byte in that chapter's text
   end record;

   --  Pages per chapter; the last one runs to the end of a longer chapter.
   Max_Pages : constant := 16_384;

   --  Open Name at At_Pos (or the book's first page), laid out in F at
   --  Size.  On failure nothing is open.
   procedure Open
     (V      : in out FS.Volume;
      Name   : String;
      F      : Truetype.Font;
      Size   : Positive;
      At_Pos : Position;
      Result : out Books.Status);

   procedure Close;

   function Is_Open return Boolean;

   --  Turn the page; Moved is False at either end of the book.
   procedure Next_Page (V : in out FS.Volume; Moved : out Boolean)
     with Pre => Is_Open;
   procedure Prev_Page (V : in out FS.Volume; Moved : out Boolean)
     with Pre => Is_Open;

   function Where return Position
     with Pre => Is_Open;

   --  The current chapter's language tag ("" if unknown).
   function Language return String;

   function Chapter return Natural;
   function Chapter_Count return Natural;
   function Page return Natural;
   function Page_Count return Natural;

   --  The current page, with Title in the status bar, and the menu over it
   --  when Menu is set.  Everything but the book's text is in UI.  With
   --  Grey, the text is anti-aliased, its grey pixels marked in Masks (see
   --  Reader_View.Draw_Page); not under the menu, which is black and white.
   procedure Draw
     (Fr    : in out Mono_Frame.Frame;
      Masks : in out Mono_Frame.Grey_Masks;
      Grey  : Boolean;
      UI    : Truetype.Font;
      Title : String;
      Batt  : Status_Bar.Battery;
      Menu  : Boolean := False)
     with Pre => Is_Open;

end Reader;
