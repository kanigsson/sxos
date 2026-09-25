with Book_Source;
with Image_FS;
with Image_Scan;

package Image_Books is new Book_Source (Image_FS, Image_Scan.Books_Folder);
