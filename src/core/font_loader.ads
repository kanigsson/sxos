with Interfaces;

with Bytes;
with Fat32;
with Font_Catalog;
with Truetype;

--  Read a face from /Fonts whole into a heap buffer and parse it.  Not SPARK:
--  it allocates.  A Truetype.Font keeps pointing into its buffer, so the
--  buffer lives as long as the font is used; Free releases it when the
--  reading face is replaced.
generic
   with package FS is new Fat32 (<>);
   Fonts_Folder : String;
package Font_Loader is

   --  Data is the font's buffer (null when Ok is False: nothing is kept).
   procedure Load
     (V     : in out FS.Volume;
      Faces : Font_Catalog.List;
      Face  : Font_Catalog.Index;
      Font  : out Truetype.Font;
      Data  : out Bytes.Byte_Array_Access;
      Ok    : out Boolean)
     with Pre => Face <= Faces.Count;

   --  For a face that is never replaced.
   procedure Load
     (V     : in out FS.Volume;
      Faces : Font_Catalog.List;
      Face  : Font_Catalog.Index;
      Font  : out Truetype.Font;
      Ok    : out Boolean)
     with Pre => Face <= Faces.Count;

   --  Whether Face has a glyph for Code, from its table directory and cmap
   --  alone: the rest of the file is not read.
   procedure Covers
     (V      : in out FS.Volume;
      Faces  : Font_Catalog.List;
      Face   : Font_Catalog.Index;
      Code   : Interfaces.Unsigned_32;
      Result : out Boolean)
     with Pre => Face <= Faces.Count;

   --  The smallest file of Faces, other than Except, that Covers Code; 0
   --  when there is none.  For the fallback face, which is read whole.
   procedure Smallest_Covering
     (V      : in out FS.Volume;
      Faces  : Font_Catalog.List;
      Code   : Interfaces.Unsigned_32;
      Except : Font_Catalog.Count_Type;
      Face   : out Font_Catalog.Count_Type)
     with Post => Face <= Faces.Count;

   --  Set the Fallback chain: a face with a glyph for Code (Reading, else
   --  Interface_Font, when that has one; else the smallest other face in
   --  /Fonts that has, loaded whole into Font and Data, Face its index),
   --  then Interface_Font.  A face loaded so is kept while later calls
   --  still need it and freed when they do not; Face is 0 and Data null
   --  when none is loaded.  Read_Face is the reading face's index (it is
   --  not probed again).
   procedure Choose_Fallback
     (V         : in out FS.Volume;
      Faces     : Font_Catalog.List;
      Code      : Interfaces.Unsigned_32;
      Interface_Font, Reading : Truetype.Font;
      Read_Face : Font_Catalog.Count_Type;
      Font      : in out Truetype.Font;
      Data      : in out Bytes.Byte_Array_Access;
      Face      : in out Font_Catalog.Count_Type);

   --  Release a buffer from Load; no font made from it may be used again.
   procedure Free (Data : in out Bytes.Byte_Array_Access)
     with Post => Bytes."=" (Data, null);

end Font_Loader;
