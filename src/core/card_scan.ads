with Fat32;
with Font_Catalog;
with Shelf;

--  What the reader needs from the card at start-up: the books in /Books and
--  the font faces in /Fonts.  Generic over the Fat32 instance, so the device
--  (SD card) and the host (disk image) run the same scan.
generic
   with package FS is new Fat32 (<>);
package Card_Scan
  with SPARK_Mode => On
is
   type Scan_Status is (OK, No_Folder, Read_Error);

   Books_Folder : constant String := "Books";
   Fonts_Folder : constant String := "Fonts";
   --  Hyphenation patterns (Hyphen_Loader); not scanned.
   Hyphenation_Folder : constant String := "Hyphenation";

   --  Readable books (Shelf.Is_Book_Name), sorted.  Subfolders are skipped.
   procedure Scan_Books
     (V : in out FS.Volume; L : out Shelf.List; Status : out Scan_Status);

   --  Regular .ttf faces, sorted.
   procedure Scan_Fonts
     (V : in out FS.Volume; C : out Font_Catalog.List; Status : out Scan_Status);

end Card_Scan;
