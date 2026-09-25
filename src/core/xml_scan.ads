--  Just enough XML to read EPUB packaging files: find tags, match their
--  names, read attribute values.  Positions are indices into the document;
--  nothing is copied.  Namespace prefixes are ignored ("opf:item" is an
--  "item").  Not a validating parser: malformed input yields odd spans,
--  never an out-of-range index.
package Xml_Scan
  with SPARK_Mode => On
is
   --  Doc (First .. Last); empty when Last < First.
   type Span is record
      First : Positive := 1;
      Last  : Natural := 0;
   end record;

   function Is_Empty (S : Span) return Boolean is (S.Last < S.First);

   function Within (Doc : String; S : Span) return Boolean is
     (Is_Empty (S) or else (S.First >= Doc'First and then S.Last <= Doc'Last));

   function Text (Doc : String; S : Span) return String is
     (if Is_Empty (S) then "" else Doc (S.First .. S.Last))
     with Pre => Within (Doc, S);

   --  Find the next tag at or after Pos.  Tag spans what is between '<' and
   --  '>'; Pos moves past the '>'.  Comments are skipped; declarations,
   --  processing instructions and CDATA come back as tags (their names
   --  match nothing).
   procedure Next_Tag
     (Doc   : String;
      Pos   : in out Positive;
      Tag   : out Span;
      Found : out Boolean)
     with Always_Terminates,
          Post => (if Found
                   then Within (Doc, Tag) and then Tag.Last < Positive'Last
                        and then Pos > Pos'Old);

   --  The subprograms below take a Tag as Next_Tag returns it: within Doc,
   --  and never ending at the last possible index, so a scan can always step
   --  one past it.

   --  Is Tag a start (or empty-element) tag named Name?
   function Is_Start (Doc : String; Tag : Span; Name : String) return Boolean
     with Pre => Within (Doc, Tag) and then Tag.Last < Positive'Last;

   --  Is Tag an end tag named Name?
   function Is_End (Doc : String; Tag : Span; Name : String) return Boolean
     with Pre => Within (Doc, Tag) and then Tag.Last < Positive'Last;

   --  The local name (prefix dropped) of Tag, and whether it is an end tag.
   --  Name is empty for declarations, comments and processing instructions.
   procedure Tag_Name
     (Doc     : String;
      Tag     : Span;
      Name    : out Span;
      Closing : out Boolean)
     with Always_Terminates,
          Pre  => Within (Doc, Tag) and then Tag.Last < Positive'Last,
          Post => Within (Doc, Name);

   --  The value of attribute Name (prefix ignored) of a start tag, without
   --  its quotes; entities are not expanded.
   procedure Attribute
     (Doc   : String;
      Tag   : Span;
      Name  : String;
      Value : out Span;
      Found : out Boolean)
     with Always_Terminates,
          Pre  => Within (Doc, Tag) and then Tag.Last < Positive'Last,
          Post => Within (Doc, Value);

   --  ASCII-case-insensitive equality.
   function Same_Text (A, B : String) return Boolean;
end Xml_Scan;
