with Bytes;
with Interfaces;

package body Font_Loader is

   procedure Load
     (V     : in out FS.Volume;
      Faces : Font_Catalog.List;
      Face  : Font_Catalog.Index;
      Font  : out Truetype.Font;
      Ok    : out Boolean)
   is
      use type Interfaces.Unsigned_32;
      F     : FS.File;
      Count : Natural;
   begin
      FS.Open (V, Fonts_Folder & "/" & Font_Catalog.File_Name (Faces, Face),
               F, Ok);
      if not Ok or else FS.Size (F) = 0 then
         Ok := False;
         return;
      end if;
      declare
         Data : constant Bytes.Byte_Array_Access :=
           new Bytes.Byte_Array (0 .. Natural (FS.Size (F)) - 1);
      begin
         FS.Read (V, F, 0, Data.all, Count, Ok);
         if not Ok or else Count /= Data'Length then
            Ok := False;
            return;
         end if;
         Truetype.Open (Truetype.Data_Ref (Data), Font, Ok);
      end;
   end Load;

end Font_Loader;
