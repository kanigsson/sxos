with Truetype;
with Truetype.Identity;
with UTF8;

--  The faces that draw what the face in use lacks: Hangul in the interface
--  face or a Western reading face, Latin accents a Korean face does not
--  have.  A short chain for the whole device, tried in order, chosen by
--  the caller (Font_Loader.Choose_Fallback: a face with Hangul, then the
--  interface face); empty at first.
--
--  Text_Raster looks here for every character its face lacks;
--  Text_Metrics copies the chain into its table when prepared.  A face
--  whose buffer is freed must be cleared here first (and Glyph_Cache
--  dropped), as for any face.
package Fallback
  with SPARK_Mode => On,
       Abstract_State => State,
       Initializes => State
is
   --  What a fallback face is chosen for: Hangul, probed with U+AC00.
   Probe : constant := 16#AC00#;

   Max_Faces : constant := 2;
   subtype Count_Type is Natural range 0 .. Max_Faces;
   subtype Index is Positive range 1 .. Max_Faces;

   procedure Clear
     with Global => (In_Out => State),
          Post   => Count = 0;

   --  Append F to the chain, unless it is there already or the chain is
   --  full.
   procedure Add (F : Truetype.Font)
     with Global => (In_Out => State,
                     Input  => Truetype.Identity.Addresses);

   function Count return Count_Type
     with Global => State;

   function Face (I : Index) return Truetype.Font
     with Global => State,
          Pre    => I <= Count;

   --  The glyph for C: in F if F has it, else in the first face of the
   --  chain that has.  Found is the face it is in (F when none has it),
   --  Source its place in the chain (0 for F), G the glyph (0 then).  Two
   --  glyphs are of the same face when their Sources are equal.
   procedure Find
     (F      : Truetype.Font;
      C      : UTF8.Code_Point;
      Found  : out Truetype.Font;
      Source : out Count_Type;
      G      : out Natural)
     with Global => State,
          Post   => G = 0 or else G < Truetype.Num_Glyphs (Found);

end Fallback;
