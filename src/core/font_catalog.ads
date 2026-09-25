with Interfaces; use Interfaces;

--  The font faces the reader can offer: the "regular" .ttf files in /Fonts.
--
--  Style variants (-Bold, -Italic, -BoldItalic, -Light, ...) are recognised
--  by the last '-' segment of the file name and left out; they are kept on
--  the card for when the reader sets emphasis.  The default face is
--  DejaVuSerif.ttf when present, else the first regular face by name.
package Font_Catalog
  with SPARK_Mode => On
is
   Max_Faces : constant := 32;
   Max_Name  : constant := 64;

   Preferred_Default : constant String := "DejaVuSerif.ttf";

   subtype Count_Type is Natural range 0 .. Max_Faces;
   subtype Index is Positive range 1 .. Max_Faces;

   type Face is record
      Name : String (1 .. Max_Name) := (others => ' ');
      Last : Natural range 0 .. Max_Name := 0;
      Size : Unsigned_32 := 0;
   end record;

   type Face_Array is array (Index) of Face;

   type List is record
      Faces : Face_Array;
      Count : Count_Type := 0;
   end record;

   procedure Clear (L : out List)
     with Post => L.Count = 0;

   --  True for a .ttf whose name does not mark a style variant.
   function Is_Regular (File_Name : String) return Boolean;

   --  Add File_Name if it is a regular .ttf (and fits); sorted by Sort.
   procedure Consider (L : in out List; File_Name : String; Size : Unsigned_32);

   procedure Sort (L : in out List);

   function File_Name (L : List; I : Index) return String
     with Pre => I <= L.Count;

   --  For the settings screen: the name without ".ttf" and "-Regular".
   function Display_Name (L : List; I : Index) return String
     with Pre  => I <= L.Count,
          Post => Display_Name'Result'First = 1
                  and then Display_Name'Result'Last <= Max_Name;

   --  The face whose file is named Name (ASCII case-insensitive), or 0.
   function Find (L : List; Name : String) return Count_Type;

   --  Preferred_Default if present, else 1; 0 for an empty list.
   function Default (L : List) return Count_Type;

end Font_Catalog;
