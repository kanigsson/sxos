with Card;
with Card_Books;
with Card_Hyphens;
with Reader;

--  The reading session.  At library level, so its state is not on the
--  64 KB environment stack.
package Card_Reader is new Reader (Card.FS, Card_Books, Card_Hyphens);
