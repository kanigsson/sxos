with Mono_Frame;
with Page_Layout;
with Status_Bar;
with Truetype;

--  The Settings screen: the reading face (step through the regular faces
--  in /Fonts with the arrows), the reading size (- / +), the reading text's
--  style (sharp black and white, or grey; either arrow switches), a sample
--  paragraph set in that face and size (black and white either way), and a
--  Done button.  The labels and buttons are in the interface face, UI; only
--  the sample is in Sample.
package Settings_View
  with SPARK_Mode => On
is
   Title : constant String := "Settings";

   procedure Draw
     (Fr        : out Mono_Frame.Frame;
      UI        : Truetype.Font;
      Sample    : Truetype.Font;
      Face_Name : String;
      Size      : Positive;
      Grey      : Boolean;
      Batt      : Status_Bar.Battery)
     with Pre => Size <= Page_Layout.Max_Size
                 and then Face_Name'Last < Positive'Last - 3;

   type Action is
     (None, Prev_Face, Next_Face, Smaller, Larger, Switch_Style, Done);

   --  What a tap at portrait (X, Y) means.
   function Action_At (X, Y : Integer) return Action;

end Settings_View;
