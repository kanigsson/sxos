--  Read-only, bounded FAT32 directory listing for the X4 Pro SD card.
package Books_List is
   Max_Entries : constant := 17;
   Max_Chars   : constant := 36;
   type Book_Entry is record
      Text : String (1 .. Max_Chars) := (others => ' ');
      Last : Natural := 0;
      Directory : Boolean := False;
   end record;
   type Entries is array (1 .. Max_Entries) of Book_Entry;
   type Result_Kind is (OK, Card_Error, Read_Error, Unsupported_FS,
                        Invalid_FS, Books_Not_Found, Empty_Directory);

   procedure Load (Items : out Entries; Count : out Natural; Result : out Result_Kind);
end Books_List;
