with Card;
with Card_Library;
with Hyphen_Loader;

--  Hyphenation patterns from the card's /Hyphenation, at library level.
package Card_Hyphens is new Hyphen_Loader
  (Card.FS, Card_Library.Hyphenation_Folder);
