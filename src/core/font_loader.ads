with Fat32;
with Font_Catalog;
with Truetype;

--  Read a face from /Fonts whole into a heap buffer and parse it.  Not SPARK:
--  it allocates.  The buffer is never freed -- a Truetype.Font keeps pointing
--  into it, and the reader loads one face per session.
generic
   with package FS is new Fat32 (<>);
   Fonts_Folder : String;
package Font_Loader is

   procedure Load
     (V     : in out FS.Volume;
      Faces : Font_Catalog.List;
      Face  : Font_Catalog.Index;
      Font  : out Truetype.Font;
      Ok    : out Boolean)
     with Pre => Face <= Faces.Count;

end Font_Loader;
