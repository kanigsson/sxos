with Fat32;
with Hyphenation;

--  Hyphenation patterns from the card: Folder holds hyph-utf8 pattern files
--  under their hyph-utf8 names (hyph-de-1996.pat.txt, hyph-en-us.pat.txt,
--  ...).  One language is loaded at a time, into a trie on the heap.  Not
--  SPARK: it allocates.
--
--  A language tag such as "en-US" or "de_DE" is looked up, lower-cased,
--  as hyph-<tag>.pat.txt, then as hyph-<primary>.pat.txt ("en"), then as
--  that language's usual variant (de: de-1996, en: en-us, el: el-monoton,
--  no: nb).
generic
   with package FS is new Fat32 (<>);
   Folder : String;
package Hyphen_Loader is

   --  The patterns for Tag (null when there are none), loaded if Tag is
   --  not the language already loaded.  The previous language's patterns
   --  are freed then: no trie from an earlier call may be used again.  An
   --  empty Tag, or one with no file, gives null without reading the card
   --  again for the same tag.
   procedure Select_Language
     (V        : in out FS.Volume;
      Tag      : String;
      Patterns : out Hyphenation.Trie_Ref);

   --  Free the loaded patterns (no trie from Select_Language may be used
   --  again); the next Select_Language reads the card afresh.
   procedure Release;

end Hyphen_Loader;
