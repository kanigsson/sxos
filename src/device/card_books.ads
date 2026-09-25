with Book_Source;
with Card;
with Card_Library;

package Card_Books is new Book_Source (Card.FS, Card_Library.Books_Folder);
