with Shelf;
with Truetype;

--  The host's stand-in for the SD card: a directory with Books/ and Fonts/
--  subdirectories, read with Ada.Directories.
package Host_Card is

   --  The first *.ttf in Root/Fonts (by name), read whole.  null if none.
   function Load_Font (Root : String) return Truetype.Data_Ref;

   --  The readable books in Root/Books, sorted.
   procedure Scan_Books (Root : String; L : out Shelf.List);

end Host_Card;
