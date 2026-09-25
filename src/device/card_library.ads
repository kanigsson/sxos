with Card;
with Card_Scan;

--  The card's /Books and /Fonts scan, instantiated at library level.
package Card_Library is new Card_Scan (Card.FS);
