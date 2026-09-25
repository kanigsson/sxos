with Interfaces;

package body Card_Scan
  with SPARK_Mode => On
is

   procedure Scan_Books
     (V : in out FS.Volume; L : out Shelf.List; Status : out Scan_Status)
   is
      Dir   : FS.File;
      Found : Boolean;
      Walk_Ok : Boolean;
      Books : Shelf.List;

      procedure Add (Name : String; F : FS.File; Stop : out Boolean) is
      begin
         Stop := False;
         if not FS.Is_Directory (F) and then Shelf.Is_Book_Name (Name) then
            Shelf.Add (Books, Name, FS.Size (F));
         end if;
      end Add;

      procedure Walk is new FS.Iterate (Add);
   begin
      Shelf.Clear (Books);
      FS.Open (V, Books_Folder, Dir, Found);
      if not Found or else not FS.Is_Directory (Dir) then
         L := Books;
         Status := No_Folder;
         return;
      end if;
      Walk (V, Dir, Walk_Ok);
      Shelf.Sort (Books);
      L := Books;
      Status := (if Walk_Ok then OK else Read_Error);
   end Scan_Books;

   procedure Scan_Fonts
     (V : in out FS.Volume; C : out Font_Catalog.List; Status : out Scan_Status)
   is
      Dir   : FS.File;
      Found : Boolean;
      Walk_Ok : Boolean;
      Faces : Font_Catalog.List;

      procedure Add (Name : String; F : FS.File; Stop : out Boolean) is
      begin
         Stop := False;
         if not FS.Is_Directory (F) then
            Font_Catalog.Consider (Faces, Name, Interfaces.Unsigned_32 (FS.Size (F)));
         end if;
      end Add;

      procedure Walk is new FS.Iterate (Add);
   begin
      Font_Catalog.Clear (Faces);
      FS.Open (V, Fonts_Folder, Dir, Found);
      if not Found or else not FS.Is_Directory (Dir) then
         C := Faces;
         Status := No_Folder;
         return;
      end if;
      Walk (V, Dir, Walk_Ok);
      Font_Catalog.Sort (Faces);
      C := Faces;
      Status := (if Walk_Ok then OK else Read_Error);
   end Scan_Fonts;

end Card_Scan;
