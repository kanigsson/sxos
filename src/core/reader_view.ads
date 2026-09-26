with Mono_Frame;
with Page_Layout;
with Status_Bar;
with Text_Metrics;
with Truetype;

--  The Reader screen: the status bar with the book's title, one page of the
--  chapter, and the page number underneath.  Tapping the top band opens a
--  menu over the page (the way to the Library and to Settings); the left
--  third of the page turns back, the rest forward.
--
--  The page's text is in the reading face F; the status bar, the page
--  number, messages and the menu in the interface face UI.
package Reader_View
  with SPARK_Mode => On
is
   Margin_X  : constant := 26;
   Text_Top  : constant := Status_Bar.Height + 16;
   Footer    : constant := 36;
   Col_Width : constant := Mono_Frame.Width - 2 * Margin_X;
   Area_Height : constant := Mono_Frame.Height - Text_Top - Footer;

   --  Justify full lines (not a paragraph's last line), unless that would
   --  stretch a space beyond Max_Stretch times its width.  Needs
   --  hyphenation: without it, ~40 characters a line leave justified text
   --  full of holes (German especially).
   Justify     : constant Boolean := True;
   Max_Stretch : constant := 3;

   --  Draw the page of Text starting at Start.  Page and Pages number it
   --  within the chapter.  With Grey, the book's text is anti-aliased: its
   --  grey pixels are marked in Masks (the rest of the screen is black and
   --  white); Masks is cleared either way.
   procedure Draw_Page
     (Fr    : out Mono_Frame.Frame;
      Masks : out Mono_Frame.Grey_Masks;
      Grey  : Boolean;
      UI    : Truetype.Font;
      F     : Truetype.Font;
      T     : Text_Metrics.Table;
      G     : Page_Layout.Geometry;
      Text  : String;
      Start : Positive;
      Title : String;
      Batt  : Status_Bar.Battery;
      Page, Pages : Natural)
     with Pre => Text'First = 1 and then Text'Last < Positive'Last
                 and then Start <= Text'Last
                 and then Text_Metrics.Size (T) <= Page_Layout.Max_Size
                 and then Title'Last < Positive'Last - 3;

   --  A page with only Message on it (a chapter that could not be read).
   procedure Draw_Message
     (Fr      : out Mono_Frame.Frame;
      UI      : Truetype.Font;
      Title   : String;
      Batt    : Status_Bar.Battery;
      Message : String)
     with Pre => Title'Last < Positive'Last - 3
                 and then Message'Last < Positive'Last;

   type Zone is (Menu, Back, Forward);

   --  What a tap at portrait (X, Y) on a page means.
   function Zone_At (X, Y : Integer) return Zone;

   --  The menu, drawn over whatever is on Fr below the status bar: where
   --  the reader is in the book, and Library and Settings buttons.
   procedure Draw_Menu
     (Fr                : in out Mono_Frame.Frame;
      UI                : Truetype.Font;
      Chapter, Chapters : Natural;
      Page, Pages       : Natural);

   type Menu_Choice is (Library, Settings, Close);

   function Menu_At (X, Y : Integer) return Menu_Choice;

end Reader_View;
