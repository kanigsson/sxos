with Mono_Frame;
with Truetype;

--  The strip across the top of every screen: a title on the left (shortened
--  with "..." when it would run into the battery), the battery on the
--  right, a rule underneath.
package Status_Bar
  with SPARK_Mode => On
is
   Height : constant := 48;   --  content starts below this

   subtype Percent is Natural range 0 .. 100;

   type Battery is record
      Known    : Boolean := False;   --  False: no gauge reading
      Level    : Percent := 0;
      Charging : Boolean := False;
   end record;

   Text_Size : constant := 24;

   procedure Draw
     (Fr    : in out Mono_Frame.Frame;
      F     : Truetype.Font;
      Title : String;
      Batt  : Battery);

   --  The battery glyph alone, right-aligned at Right with its vertical
   --  centre at Mid.  Drawn with rectangles, so it needs no font.
   procedure Draw_Battery
     (Fr : in out Mono_Frame.Frame; Right, Mid : Integer; Batt : Battery);

end Status_Bar;
