with Text_Raster;

package body Settings_View
  with SPARK_Mode => On
is
   Margin     : constant := 24;
   Label_Size : constant := 22;
   Value_Size : constant := 26;

   --  A row: a square button at each end, the value between them.
   Button   : constant := 70;
   Left_X   : constant := Margin;
   Right_X  : constant := Mono_Frame.Width - Margin - Button;
   Face_Y   : constant := Status_Bar.Height + 64;
   Size_Y   : constant := Face_Y + Button + 76;

   --  The sample, between two rules.
   Sample_Top    : constant := Size_Y + Button + 28;
   Sample_Bottom : constant := Mono_Frame.Height - 110;
   Sample_X      : constant := 26;   --  the Reader's margin

   Done_X : constant := 40;
   Done_Y : constant := Mono_Frame.Height - 90;
   Done_W : constant := Mono_Frame.Width - 2 * Done_X;
   Done_H : constant := 70;

   Sample_Text : constant String :=
     "It was the best of times, it was the worst of times, it was the age "
     & "of wisdom, it was the age of foolishness. "
     & "Größe, Fähre, «déjà vu» — Ελληνικά, кириллица.";

   --  N in decimal, without 'Image's leading space.  A Natural's 'Image
   --  has at most 11 characters; the bound on the slice says so to the
   --  prover, so that callers can concatenate the result.
   function Image (N : Natural) return String
     with Post => Image'Result'First = 2 and then Image'Result'Length <= 10
   is
      S : constant String := Natural'Image (N);
   begin
      return S (S'First + 1 .. Integer'Min (S'Last, S'First + 10));
   end Image;

   procedure Box (Fr : in out Mono_Frame.Frame; X, Y, W, H : Integer)
     with Pre => X in 0 .. Mono_Frame.Width
                 and then Y in 0 .. Mono_Frame.Height
                 and then W in 2 .. Mono_Frame.Width
                 and then H in 2 .. Mono_Frame.Height
   is
   begin
      Mono_Frame.Frame_Rect (Fr, X, Y, W, H);
      Mono_Frame.Frame_Rect (Fr, X + 1, Y + 1, W - 2, H - 2);
   end Box;

   --  A solid triangle in a button at (X, Y), pointing left or right.
   procedure Arrow (Fr : in out Mono_Frame.Frame; X, Y : Integer;
                    Left : Boolean)
     with Pre => X in 0 .. Mono_Frame.Width
                 and then Y in 0 .. Mono_Frame.Height
   is
      Half : constant := 14;   --  half height; the width is the same
      CX   : constant Integer := X + Button / 2;
      CY   : constant Integer := Y + Button / 2;
      W    : Natural;
   begin
      for Row in -Half .. Half loop
         W := Half - abs Row;
         if Left then
            Mono_Frame.Fill_Rect
              (Fr, CX - Half / 2 + (Half - W), CY + Row, W + 1, 1);
         else
            Mono_Frame.Fill_Rect (Fr, CX - Half / 2, CY + Row, W + 1, 1);
         end if;
      end loop;
   end Arrow;

   procedure Minus (Fr : in out Mono_Frame.Frame; X, Y : Integer)
     with Pre => X in 0 .. Mono_Frame.Width
                 and then Y in 0 .. Mono_Frame.Height
   is
   begin
      Mono_Frame.Fill_Rect (Fr, X + Button / 2 - 14, Y + Button / 2 - 2, 28, 4);
   end Minus;

   procedure Plus (Fr : in out Mono_Frame.Frame; X, Y : Integer)
     with Pre => X in 0 .. Mono_Frame.Width
                 and then Y in 0 .. Mono_Frame.Height
   is
   begin
      Minus (Fr, X, Y);
      Mono_Frame.Fill_Rect (Fr, X + Button / 2 - 2, Y + Button / 2 - 14, 4, 28);
   end Plus;

   --  Str centred between the two buttons of the row at Y, shortened with
   --  "..." if it does not fit.
   procedure Row_Value
     (Fr : in out Mono_Frame.Frame; F : Truetype.Font; Y : Integer;
      Str : String)
     with Pre => Y in 0 .. Mono_Frame.Height
                 and then Str'Last < Positive'Last - 3
   is
      Left     : constant Integer := Left_X + Button + 8;
      Right    : constant Integer := Right_X - 8;
      Asc      : constant Natural := Text_Raster.Ascent_Px (F, Value_Size);
      Desc     : constant Natural := Text_Raster.Descent_Px (F, Value_Size);
      Baseline : constant Integer := Y + (Button + Asc - Desc) / 2;
      Ellipsis : constant String := "...";
      Cut      : Natural;
   begin
      if Text_Raster.Width (F, Value_Size, Str) <= Right - Left then
         Text_Raster.Draw_Centered
           (Fr, F, Value_Size, Left, Right, Baseline, Str);
      else
         Cut := Text_Raster.Fit
           (F, Value_Size, Str,
            Natural'Max (0, Right - Left
                            - Text_Raster.Width (F, Value_Size, Ellipsis)));
         Text_Raster.Draw_Centered
           (Fr, F, Value_Size, Left, Right, Baseline,
            Str (Str'First .. Cut) & Ellipsis);
      end if;
   end Row_Value;

   --  The sample paragraph, set like the Reader sets text (1.35 em from
   --  baseline to baseline) as far as it fits.
   procedure Draw_Sample
     (Fr : in out Mono_Frame.Frame; F : Truetype.Font; Size : Positive)
     with Pre => Size <= Page_Layout.Max_Size
   is
      Asc   : constant Natural := Text_Raster.Ascent_Px (F, Size);
      Desc  : constant Natural := Text_Raster.Descent_Px (F, Size);
      LH    : constant Positive :=
        Positive'Max (Text_Raster.Line_Height_Px (F, Size),
                      (Size * 135 + 50) / 100);
      Max_W : constant := Mono_Frame.Width - 2 * Sample_X;
      Y     : Integer := Sample_Top + 16 + (LH - Asc - Desc) / 2 + Asc;
      From  : Positive := Sample_Text'First;
      First : Positive;
      Last  : Natural;
      Next  : Positive;
   begin
      while From <= Sample_Text'Last and then Y + Desc < Sample_Bottom loop
         pragma Loop_Invariant (Y < Sample_Bottom);
         pragma Loop_Variant (Increases => From);
         Text_Raster.Wrap_Line
           (F, Size, Sample_Text, From, Max_W, First, Last, Next);
         exit when Last < First;
         Text_Raster.Draw_Text
           (Fr, F, Size, Sample_X, Y, Sample_Text (First .. Last));
         exit when Next <= From;
         From := Next;
         Y := Y + LH;
      end loop;
   end Draw_Sample;

   procedure Draw
     (Fr        : out Mono_Frame.Frame;
      UI        : Truetype.Font;
      Sample    : Truetype.Font;
      Face_Name : String;
      Size      : Positive;
      Batt      : Status_Bar.Battery)
   is
      Asc  : constant Natural := Text_Raster.Ascent_Px (UI, Value_Size);
      Desc : constant Natural := Text_Raster.Descent_Px (UI, Value_Size);
   begin
      Mono_Frame.Clear (Fr);
      Status_Bar.Draw (Fr, UI, Title, Batt);

      Text_Raster.Draw_Text
        (Fr, UI, Label_Size, Margin, Face_Y - 14, "Reading font");
      Box (Fr, Left_X, Face_Y, Button, Button);
      Arrow (Fr, Left_X, Face_Y, Left => True);
      Box (Fr, Right_X, Face_Y, Button, Button);
      Arrow (Fr, Right_X, Face_Y, Left => False);
      Row_Value (Fr, UI, Face_Y, Face_Name);

      Text_Raster.Draw_Text
        (Fr, UI, Label_Size, Margin, Size_Y - 14, "Reading size");
      Box (Fr, Left_X, Size_Y, Button, Button);
      Minus (Fr, Left_X, Size_Y);
      Box (Fr, Right_X, Size_Y, Button, Button);
      Plus (Fr, Right_X, Size_Y);
      Row_Value (Fr, UI, Size_Y, Image (Size) & " px");

      Mono_Frame.Fill_Rect (Fr, Margin, Sample_Top, Mono_Frame.Width - 2 * Margin, 1);
      Draw_Sample (Fr, Sample, Size);
      Mono_Frame.Fill_Rect
        (Fr, Margin, Sample_Bottom, Mono_Frame.Width - 2 * Margin, 1);

      Box (Fr, Done_X, Done_Y, Done_W, Done_H);
      Text_Raster.Draw_Centered
        (Fr, UI, Value_Size, Done_X, Done_X + Done_W,
         Done_Y + (Done_H + Asc - Desc) / 2, "Done");
   end Draw;

   function In_Box (X, Y, BX, BY, W, H : Integer) return Boolean is
     (X in BX .. BX + W - 1 and then Y in BY .. BY + H - 1)
     with Pre => BX in 0 .. Mono_Frame.Width
                 and then BY in 0 .. Mono_Frame.Height
                 and then W in 0 .. Mono_Frame.Width
                 and then H in 0 .. Mono_Frame.Height;

   --  Buttons take taps a little outside their frames too.
   Slack : constant := 12;

   function Action_At (X, Y : Integer) return Action is
     (if In_Box (X, Y, Left_X - Slack, Face_Y - Slack,
                 Button + 2 * Slack, Button + 2 * Slack) then Prev_Face
      elsif In_Box (X, Y, Right_X - Slack, Face_Y - Slack,
                    Button + 2 * Slack, Button + 2 * Slack) then Next_Face
      elsif In_Box (X, Y, Left_X - Slack, Size_Y - Slack,
                    Button + 2 * Slack, Button + 2 * Slack) then Smaller
      elsif In_Box (X, Y, Right_X - Slack, Size_Y - Slack,
                    Button + 2 * Slack, Button + 2 * Slack) then Larger
      elsif In_Box (X, Y, Done_X, Done_Y - Slack, Done_W, Done_H + 2 * Slack)
      then Done
      else None);

end Settings_View;
