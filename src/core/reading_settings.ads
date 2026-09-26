with Interfaces; use Interfaces;

with Font_Catalog;
with Store_Record;

--  The reading settings -- the face and the size of the reading text, and
--  whether it is drawn in grey (anti-aliased) -- and their store record
--  (under Store_Record.Settings_Key).
--
--  The face is kept as a hash of its file name, not as an index into
--  /Fonts, so adding or removing fonts does not change it; a face that is no
--  longer on the card falls back to the default.
package Reading_Settings
  with SPARK_Mode => On
is
   Min_Size     : constant := 16;
   Max_Size     : constant := 48;
   Size_Step    : constant := 2;
   Default_Size : constant := 24;

   subtype Size_Type is Positive range Min_Size .. Max_Size;

   type Values is record
      Size : Size_Type := Default_Size;
      Face : Unsigned_32 := 0;   --  Face_Hash; 0: the default face
      Grey : Boolean := False;
   end record;

   function Smaller (S : Size_Type) return Size_Type is
     (if S - Size_Step >= Min_Size then S - Size_Step else Min_Size);

   function Larger (S : Size_Type) return Size_Type is
     (if S + Size_Step <= Max_Size then S + Size_Step else Max_Size);

   --  FNV-1a of the file name, ASCII case folded (as Font_Catalog.Find
   --  matches names); never 0.
   function Face_Hash (L : Font_Catalog.List; I : Font_Catalog.Index)
     return Unsigned_32
     with Pre => I <= L.Count;

   --  The face whose hash is H, or 0.
   function Find_Face (L : Font_Catalog.List; H : Unsigned_32)
     return Font_Catalog.Count_Type;

   --  (size, face hash, 1 if grey else 0, 0)
   function To_Payload (V : Values) return Store_Record.Payload;

   --  A payload out of range gives the defaults.
   function From_Payload (P : Store_Record.Payload) return Values;

end Reading_Settings;
