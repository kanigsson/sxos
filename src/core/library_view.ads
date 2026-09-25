with Mono_Frame;
with Shelf;
with Status_Bar;
with Truetype;

--  The Library screen: the status bar, one page of book titles with the
--  selected one on an inverted bar, and a footer with a page indicator
--  (when the list needs more than one page) and a Settings button.  Row geometry follows the font's metrics, so
--  it is computed rather than fixed; Book_At is the matching hit test.
package Library_View
  with SPARK_Mode => On
is
   Name_Size : constant := 28;
   Title     : constant String := "Library";

   function Rows_Per_Page (F : Truetype.Font) return Positive;

   --  The book whose row covers portrait Y on the page that shows Selected,
   --  or 0 for none.
   function Book_At
     (F : Truetype.Font; L : Shelf.List; Selected : Natural; Y : Integer)
      return Natural;

   --  Whether portrait (X, Y) is on the Settings button.
   function Settings_At (X, Y : Integer) return Boolean;

   --  Selected = 0 highlights nothing.  With an empty list, Message is
   --  shown instead (e.g. why the card could not be read).
   procedure Draw
     (Fr       : in out Mono_Frame.Frame;
      F        : Truetype.Font;
      L        : Shelf.List;
      Selected : Natural;
      Batt     : Status_Bar.Battery;
      Message  : String := "No books in /Books");

end Library_View;
