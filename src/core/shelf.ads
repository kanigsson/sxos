with Interfaces; use Interfaces;

--  The books found in /Books: a bounded list of file names, sorted for
--  display.  Names are UTF-8.  Only files the reader can open (.epub, .txt)
--  belong here; the scanner filters with Is_Book_Name.
package Shelf
  with SPARK_Mode => On
is
   Max_Books : constant := 256;
   Max_Name  : constant := 128;   --  bytes of UTF-8; longer names are cut

   subtype Count_Type is Natural range 0 .. Max_Books;
   subtype Index is Positive range 1 .. Max_Books;
   subtype Name_Length is Natural range 0 .. Max_Name;

   type Book is record
      Name : String (1 .. Max_Name) := (others => ' ');
      Last : Name_Length := 0;
      Size : Unsigned_32 := 0;       --  file size, part of the saved-state key
   end record;

   type Book_Array is array (Index) of Book;

   type List is record
      Books : Book_Array;
      Count : Count_Type := 0;
   end record;

   procedure Clear (L : out List)
     with Post => L.Count = 0;

   --  Append, unless the list is full (then the book is dropped).  A name
   --  longer than Max_Name is cut at a UTF-8 code-point boundary.
   procedure Add (L : in out List; Name : String; Size : Unsigned_32);

   function Name (L : List; I : Index) return String
     with Pre => I <= L.Count;

   --  Name without its extension, for display.
   function Title (L : List; I : Index) return String
     with Pre => I <= L.Count;

   --  Case-insensitive (ASCII letters) byte order.
   procedure Sort (L : in out List);

   --  True for *.epub and *.txt, any letter case.
   function Is_Book_Name (Name : String) return Boolean;

   type Book_Format is (EPUB, TXT, Unknown);
   function Format_Of (Name : String) return Book_Format;

end Shelf;
