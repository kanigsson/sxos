with Bytes;
with Interfaces; use Interfaces;
with UTF8;

--  Hyphenation points of a word by Liang's algorithm (the one TeX uses),
--  from a pattern file in the hyph-utf8 plain-text form (hyph-XX.pat.txt:
--  UTF-8 patterns such as ".ab3a" or "4b1ba" separated by white space).
--
--  The patterns become a letter trie.  Measure sizes it from the file's
--  text; the caller allocates a Trie of that size (it is large: about 13
--  bytes a node, 58 000 nodes for German) and Build fills it in.
--
--  Letters are compared after Fold, a lower-casing for Latin, Greek and
--  Cyrillic; code points the patterns never use match nothing.
package Hyphenation
  with SPARK_Mode => On
is
   --  Longer words are not hyphenated; longer patterns are skipped.
   Max_Word    : constant := 40;
   Max_Pattern : constant := 40;

   --  A code point's index in the patterns' alphabet; 0 is not in it.
   subtype Letter is Unsigned_8;

   --  Code points up to here map through a table; the few above it that a
   --  pattern file uses (e.g. U+2019) are kept in a short list.
   Direct_Last : constant := 16#52F#;
   Max_Extra   : constant := 32;

   type Letter_Map is array (UTF8.Code_Point range 0 .. Direct_Last) of Letter;
   type Root_Array is array (Letter) of Natural;
   type Letter_Array is array (Positive range <>) of Letter;
   type Link_Array is array (Positive range <>) of Natural;
   type Extra_Codes is array (1 .. Max_Extra) of UTF8.Code_Point;
   type Extra_Letters is array (1 .. Max_Extra) of Letter;

   --  Nodes are 1 .. Used (0 is "none").  A node's children are a list
   --  through Sibling starting at Child; the first letter of a pattern is
   --  looked up directly in Root.  A node ending a pattern has Value, the
   --  index in Pool of that pattern's Depth + 1 digits (else 0).
   type Trie (Nodes : Natural; Pool_Size : Natural) is record
      Left_Min, Right_Min : Positive;   --  letters kept before / after a break
      Used, Pool_Used     : Natural;
      Alphabet            : Letter;     --  letters in use: 1 .. Alphabet
      Map                 : Letter_Map;
      Extra_Count         : Natural range 0 .. Max_Extra;
      Extra_Code          : Extra_Codes;
      Extra_Letter        : Extra_Letters;
      Root                : Root_Array;
      Node_Letter         : Letter_Array (1 .. Nodes);
      Child, Sibling      : Link_Array (1 .. Nodes);
      Value               : Link_Array (1 .. Nodes);
      Pool                : Bytes.Byte_Array (1 .. Pool_Size);
   end record;

   type Trie_Ref is access constant Trie;

   --  The trie size Text needs (an upper bound; exact when the patterns are
   --  sorted, as the hyph-utf8 files are).
   procedure Measure (Text : String; Nodes, Pool_Size : out Natural)
     with Pre => Text'Last < Positive'Last;

   --  Fill T, allocated with Measure's sizes, from Text.  Ok is False if
   --  Text holds no pattern or more than 255 distinct letters.
   procedure Build
     (Text                : String;
      Left_Min, Right_Min : Positive;
      T                   : in out Trie;
      Ok                  : out Boolean)
     with Pre => Text'Last < Positive'Last;

   type Code_Array is array (Positive range <>) of UTF8.Code_Point;
   type Break_Array is array (Positive range <>) of Boolean;

   --  Breaks (I): Word may be broken after its I-th letter.  Word holds
   --  letters only (Is_Letter), in any case.
   procedure Hyphenate
     (T      : Trie;
      Word   : Code_Array;
      Breaks : out Break_Array)
     with Pre => Word'First = 1 and then Word'Length <= Max_Word
                 and then Breaks'First = 1 and then Breaks'Last = Word'Last;

   --  A letter of a word for hyphenation: Latin, Greek or Cyrillic.
   function Is_Letter (C : UTF8.Code_Point) return Boolean;

   --  Lower case, for the letters Is_Letter accepts; C itself otherwise.
   function Fold (C : UTF8.Code_Point) return UTF8.Code_Point;

end Hyphenation;
