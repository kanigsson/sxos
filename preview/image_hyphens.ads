with Hyphen_Loader;
with Image_FS;
with Image_Scan;

package Image_Hyphens is new Hyphen_Loader
  (Image_FS, Image_Scan.Hyphenation_Folder);
