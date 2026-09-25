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

   --  Release a buffer from Load; no font made from it may be used again.
   procedure Free (Data : in out Bytes.Byte_Array_Access)
     with Post => Bytes."=" (Data, null);

end Font_Loader;
