--  Which language a text is in, for a book whose metadata does not say
--  (a TXT file, an EPUB without <dc:language>): count the most common short
--  words of a few European languages in its first Sample bytes.
package Language_Guess
  with SPARK_Mode => On
is
   Sample : constant := 32 * 1024;

   type Language is (Unknown, English, German, French, Spanish, Italian,
                     Dutch, Russian);

   --  Unknown unless one language's words are frequent (at least
   --  Min_Hits) and twice as frequent as any other's.
   Min_Hits : constant := 20;

   function Guess (Text : String) return Language;

   --  The ISO 639-1 code ("en", "de", ...); "" for Unknown.
   function Code (L : Language) return String;

end Language_Guess;
