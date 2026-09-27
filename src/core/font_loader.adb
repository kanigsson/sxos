with Ada.Unchecked_Deallocation;
with Interfaces;

with Fallback;
with Glyph_Cache;

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
      begin
         Data := new Bytes.Byte_Array (0 .. Natural (FS.Size (F)) - 1);
      exception
         when Storage_Error =>
            --  No free block that large (the heap may be fragmented).
            Ok := False;
            return;
      end;
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

   procedure Covers
     (V      : in out FS.Volume;
      Faces  : Font_Catalog.List;
      Face   : Font_Catalog.Index;
      Code   : Interfaces.Unsigned_32;
      Result : out Boolean)
   is
      use type Interfaces.Unsigned_32;
      --  Room for a directory of 256 tables; fonts have some 20.
      Header : Bytes.Byte_Array (0 .. 12 + 16 * 256 - 1);
      --  No real cmap comes near this (Noto Sans KR's: 29 KB).
      Max_Cmap : constant := 1024 * 1024;
      F       : FS.File;
      Count   : Natural;
      Ok      : Boolean;
      Off, Len : Natural;
      Cmap    : Bytes.Byte_Array_Access;
      Probe   : Truetype.Font;
   begin
      Result := False;
      FS.Open (V, Fonts_Folder & "/" & Font_Catalog.File_Name (Faces, Face),
               F, Ok);
      if not Ok then
         return;
      end if;
      FS.Read (V, F, 0, Header, Count, Ok);
      if not Ok then
         return;
      end if;
      Truetype.Find_Cmap (Header (0 .. Count - 1), Off, Len, Ok);
      if not Ok or else Len > Max_Cmap
        or else Interfaces.Unsigned_32 (Off) + Interfaces.Unsigned_32 (Len)
                > FS.Size (F)
      then
         return;
      end if;
      begin
         Cmap := new Bytes.Byte_Array (0 .. Len - 1);
      exception
         when Storage_Error =>
            return;
      end;
      FS.Read (V, F, Interfaces.Unsigned_32 (Off), Cmap.all, Count, Ok);
      if Ok and then Count = Len then
         Truetype.Open_Cmap (Truetype.Data_Ref (Cmap), Probe, Ok);
         Result := Ok and then Truetype.Glyph_Index (Probe, Code) /= 0;
      end if;
      Release (Cmap);
   end Covers;

   procedure Smallest_Covering
     (V      : in out FS.Volume;
      Faces  : Font_Catalog.List;
      Code   : Interfaces.Unsigned_32;
      Except : Font_Catalog.Count_Type;
      Face   : out Font_Catalog.Count_Type)
   is
      use type Interfaces.Unsigned_32;
      Has : Boolean;
   begin
      Face := 0;
      for I in 1 .. Faces.Count loop
         if I /= Except
           and then (Face = 0
                     or else Faces.Faces (I).Size < Faces.Faces (Face).Size)
         then
            Covers (V, Faces, I, Code, Has);
            if Has then
               Face := I;
            end if;
         end if;
      end loop;
   end Smallest_Covering;

   procedure Choose_Fallback
     (V         : in out FS.Volume;
      Faces     : Font_Catalog.List;
      Code      : Interfaces.Unsigned_32;
      Interface_Font, Reading : Truetype.Font;
      Read_Face : Font_Catalog.Count_Type;
      Font      : in out Truetype.Font;
      Data      : in out Bytes.Byte_Array_Access;
      Face      : in out Font_Catalog.Count_Type)
   is
      use type Bytes.Byte_Array_Access;
      Pick : Font_Catalog.Count_Type;
      Ok   : Boolean;
   begin
      Fallback.Clear;
      if Truetype.Glyph_Index (Reading, Code) /= 0 then
         Fallback.Add (Reading);
      elsif Truetype.Glyph_Index (Interface_Font, Code) = 0 then
         if Data = null then
            Smallest_Covering (V, Faces, Code, Read_Face, Pick);
            if Pick /= 0 then
               Load (V, Faces, Pick, Font, Data, Ok);
               if Ok then
                  Face := Pick;
               end if;
            end if;
         end if;
         if Data /= null then
            Fallback.Add (Font);
         end if;
      end if;
      --  Last, the interface face (for the Latin a Korean face lacks).
      Fallback.Add (Interface_Font);

      --  A face loaded before and no longer needed.
      if Data /= null
        and then (Truetype.Glyph_Index (Reading, Code) /= 0
                  or else Truetype.Glyph_Index (Interface_Font, Code) /= 0)
      then
         Glyph_Cache.Drop;
         Release (Data);
         Face := 0;
      end if;
   end Choose_Fallback;

   procedure Free (Data : in out Bytes.Byte_Array_Access) is
   begin
      Release (Data);
   end Free;

end Font_Loader;
