with Mono_Frame;
with Status_Bar;
with Toc;
with Truetype;

--  The Contents screen: the status bar with the book's title, one page of
--  the table of contents (entries indented by level, the selected one on
--  an inverted bar, the one being read marked in the left margin), and a
--  footer with a page indicator (with arrows, when the list needs more than
--  one page) and a Back button.  Laid out as the Library: row geometry
--  follows the font's metrics; Entry_At is the matching hit test.
package Toc_View
  with SPARK_Mode => On
is
   Entry_Size : constant := 24;

   function Rows_Per_Page (F : Truetype.Font) return Positive;

   --  The entry whose row covers portrait Y on the page that shows
   --  Selected, of Count entries, or 0 for none.
   function Entry_At
     (F : Truetype.Font; Count, Selected : Natural; Y : Integer)
      return Natural;

   --  -1 / 1 when portrait (X, Y) is on the previous / next page arrow
   --  (whether or not they are shown), else 0.
   function Page_Step_At (X, Y : Integer) return Integer;

   --  The first entry of the page Step (-1 or 1) away from Selected's, or
   --  Selected when there is no such page.
   function Page_Target
     (F : Truetype.Font; Count, Selected : Natural; Step : Integer)
      return Natural;

   --  Whether portrait (X, Y) is on the Back button.
   function Back_At (X, Y : Integer) return Boolean;

   --  Entry I is Lines (I), its label Labels (Lines (I).First ..
   --  Lines (I).Last).  Here (0: none) is the entry being read.
   procedure Draw
     (Fr       : out Mono_Frame.Frame;
      F        : Truetype.Font;
      Title    : String;
      Labels   : String;
      Lines    : Toc.Line_Array;
      Selected : Natural;
      Here     : Natural;
      Batt     : Status_Bar.Battery)
     with Pre => Title'Last < Positive'Last - 3
                 and then Labels'Last < Positive'Last - 3
                 and then Lines'First = 1
                 and then (for all L of Lines =>
                             L.Last < L.First
                             or else (L.First >= Labels'First
                                      and then L.Last <= Labels'Last));

end Toc_View;
