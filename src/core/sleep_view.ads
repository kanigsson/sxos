with Mono_Frame;
with Status_Bar;
with Truetype;

--  What stays on the glass while the device sleeps: the status bar with
--  Title (the open book, or the Library), and a note that the power button
--  wakes the reader.
package Sleep_View
  with SPARK_Mode => On
is
   procedure Draw
     (Fr    : out Mono_Frame.Frame;
      UI    : Truetype.Font;
      Title : String;
      Batt  : Status_Bar.Battery)
     with Pre => Title'Last < Positive'Last - 3;
end Sleep_View;
