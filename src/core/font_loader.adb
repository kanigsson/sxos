with Ada.Unchecked_Deallocation;
with Interfaces;

package body Font_Loader is

   procedure Release is new Ada.Unchecked_Deallocation
     (Bytes.Byte_Array, Bytes.Byte_Array_Access);

   procedure Load
     (V     : in out FS.Volume;
      Faces : Font_Catalog.List;
      Face  : Font_Catalog.Index;
      Font  : out Truetype.Font;
      Data  : out Bytes.Byte_Array_Access;
      Ok    : out Boolean)
   is
      use type Interfaces.Unsigned_32;
      F     : FS.File;
      Count : Natural;
   begin
      Data := null;
      FS.Open (V, Fonts_Folder & "/" & Font_Catalog.File_Name (Faces, Face),
               F, Ok);
      if not Ok or else FS.Size (F) = 0 then
         Ok := False;
         return;
      end if;
      Data := new Bytes.Byte_Array (0 .. Natural (FS.Size (F)) - 1);
      FS.Read (V, F, 0, Data.all, Count, Ok);
      if Ok and then Count = Data'Length then
         Truetype.Open (Truetype.Data_Ref (Data), Font, Ok);
      else
         Ok := False;
      end if;
      if not Ok then
         Release (Data);
      end if;
   end Load;

   procedure Load
     (V     : in out FS.Volume;
      Faces : Font_Catalog.List;
      Face  : Font_Catalog.Index;
      Font  : out Truetype.Font;
      Ok    : out Boolean)
   is
      Data : Bytes.Byte_Array_Access;
   begin
      Load (V, Faces, Face, Font, Data, Ok);
   end Load;

   procedure Free (Data : in out Bytes.Byte_Array_Access) is
   begin
      Release (Data);
   end Free;

end Font_Loader;
