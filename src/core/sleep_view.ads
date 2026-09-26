with Mono_Frame;
with Status_Bar;
with Truetype;

--  What stays on the glass while the device sleeps or is off: the status
--  bar with Title (the open book, or the Library), and a note on how the
--  power button wakes it (a press) or turns it on (a long press).
package Sleep_View
  with SPARK_Mode => On
is
   procedure Draw
     (Fr    : out Mono_Frame.Frame;
      UI    : Truetype.Font;
      Title : String;
      Batt  : Status_Bar.Battery;
      Off   : Boolean := False)
     with Pre => Title'Last < Positive'Last - 3;
end Sleep_View;
