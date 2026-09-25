with Glyph_Cache;
with Text_Raster;
with UTF8;

package body Reader_View
  with SPARK_Mode => On
is
   use type UTF8.Code_Point;

   Foot_Size : constant := 20;
   Menu_Size : constant := 26;

   --  The menu panel and its two buttons, side by side.
   Panel_Top    : constant := Status_Bar.Height;
   Panel_Height : constant := 190;
   Button_X     : constant := 30;
   Button_Gap   : constant := 20;
   Button_Y     : constant := Panel_Top + 90;
   Button_W     : constant := (Mono_Frame.Width - 2 * Button_X - Button_Gap) / 2;
   Button_H     : constant := 70;
   Button_2_X   : constant := Button_X + Button_W + Button_Gap;

   --  Taps above this line open the menu.
   Menu_Band : constant := Status_Bar.Height + 40;

   function Image (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Image;

   --  One line, with the extra width of a justified line spread over its
   --  spaces (the first Extra mod Spaces spaces get one pixel more), and the
   --  hyphen of a word broken at its end.
   procedure Draw_Line
     (Fr       : in out Mono_Frame.Frame;
      F        : Truetype.Font;
      T        : Text_Metrics.Table;
      G        : Page_Layout.Geometry;
      Text     : String;
      L        : Page_Layout.Line;
      Baseline : Integer)
     with Pre => Text'First = 1 and then L.Last <= Text'Last
   is
      Size    : constant Positive := Text_Metrics.Size (T);
      Gain    : constant Positive := Text_Raster.Gain_For (Size);
      Space_W : constant Natural :=
        Text_Metrics.Advance (T, F, Character'Pos (' '));
      Budget  : constant Integer :=
        G.Col_Width - (if L.Indented then G.Indent else 0);
      Extra   : Natural := 0;
      Share   : Natural := 0;
      Rest    : Natural := 0;
      X       : Integer := Margin_X + (if L.Indented then G.Indent else 0);
      P       : Positive := L.First;
      C       : UTF8.Code_Point;
      Gl      : Natural;
      Adv     : Natural;
   begin
      if Justify and then not L.Para_End and then L.Spaces > 0
        and then Budget > L.Width
      then
         Extra := Budget - L.Width;
         if Extra / L.Spaces <= Max_Stretch * Space_W then
            Share := Extra / L.Spaces;
            Rest := Extra mod L.Spaces;
         end if;
      end if;

      while P <= L.Last loop
         if Text (P) = ' ' then
            X := X + Space_W + Share;
            if Rest > 0 then
               X := X + 1;
               Rest := Rest - 1;
            end if;
            P := P + 1;
         else
            UTF8.Next_Code (Text, P, C);
            Gl := Text_Metrics.Glyph (T, F, C);
            if Gl /= 0 then
               Glyph_Cache.Draw
                 (Fr, F, Gl, Size, Gain, Text_Raster.Ink_Threshold,
                  X, Baseline, True, Adv);
            end if;
            X := X + Text_Metrics.Advance (T, F, C);
         end if;
      end loop;

      if L.Hyphen then
         Gl := Text_Metrics.Glyph (T, F, Character'Pos ('-'));
         if Gl /= 0 then
            Glyph_Cache.Draw
              (Fr, F, Gl, Size, Gain, Text_Raster.Ink_Threshold,
               X, Baseline, True, Adv);
         end if;
      end if;
   end Draw_Line;

   procedure Draw_Footer
     (Fr : in out Mono_Frame.Frame; UI : Truetype.Font; Page, Pages : Natural)
   is
   begin
      if Pages > 0 then
         Text_Raster.Draw_Centered
           (Fr, UI, Foot_Size, 0, Mono_Frame.Width, Mono_Frame.Height - 12,
            Image (Page) & " / " & Image (Pages));
      end if;
   end Draw_Footer;

   procedure Draw_Page
     (Fr    : in out Mono_Frame.Frame;
      UI    : Truetype.Font;
      F     : Truetype.Font;
      T     : Text_Metrics.Table;
      G     : Page_Layout.Geometry;
      Text  : String;
      Start : Positive;
      Title : String;
      Batt  : Status_Bar.Battery;
      Page, Pages : Natural)
   is
      --  Page_End decides where the page stops, so drawing and pagination
      --  can never disagree.
      Stop : constant Positive := Page_Layout.Page_End (T, F, G, Text, Start);
      P    : Positive := Start;
      Y    : Integer := Text_Top;
      L    : Page_Layout.Line;
   begin
      Mono_Frame.Clear (Fr);
      Status_Bar.Draw (Fr, UI, Title, Batt);
      while P < Stop loop
         Page_Layout.Break_Line (T, F, G, Text, P, L);
         Draw_Line (Fr, F, T, G, Text, L, Y + G.Ascent);
         Y := Y + G.Line_Height + (if L.Para_End then G.Para_Gap else 0);
         P := L.Next;
      end loop;
      Draw_Footer (Fr, UI, Page, Pages);
   end Draw_Page;

   procedure Draw_Message
     (Fr      : in out Mono_Frame.Frame;
      UI      : Truetype.Font;
      Title   : String;
      Batt    : Status_Bar.Battery;
      Message : String) is
   begin
      Mono_Frame.Clear (Fr);
      Status_Bar.Draw (Fr, UI, Title, Batt);
      Text_Raster.Draw_Centered
        (Fr, UI, Menu_Size, 0, Mono_Frame.Width, Mono_Frame.Height / 2,
         Message);
   end Draw_Message;

   function Zone_At (X, Y : Integer) return Zone is
     (if Y < Menu_Band then Menu
      elsif X < Mono_Frame.Width / 3 then Back
      else Forward);

   procedure Draw_Button
     (Fr : in out Mono_Frame.Frame; UI : Truetype.Font; X : Integer;
      Label : String)
   is
      Asc  : constant Natural := Text_Raster.Ascent_Px (UI, Menu_Size);
      Desc : constant Natural := Text_Raster.Descent_Px (UI, Menu_Size);
   begin
      Mono_Frame.Frame_Rect (Fr, X, Button_Y, Button_W, Button_H);
      Mono_Frame.Frame_Rect
        (Fr, X + 1, Button_Y + 1, Button_W - 2, Button_H - 2);
      Text_Raster.Draw_Centered
        (Fr, UI, Menu_Size, X, X + Button_W,
         Button_Y + (Button_H + Asc - Desc) / 2, Label);
   end Draw_Button;

   procedure Draw_Menu
     (Fr                : in out Mono_Frame.Frame;
      UI                : Truetype.Font;
      Chapter, Chapters : Natural;
      Page, Pages       : Natural)
   is
   begin
      Mono_Frame.Fill_Rect
        (Fr, 0, Panel_Top, Mono_Frame.Width, Panel_Height, Black => False);
      Mono_Frame.Fill_Rect
        (Fr, 0, Panel_Top + Panel_Height - 3, Mono_Frame.Width, 3);

      Text_Raster.Draw_Centered
        (Fr, UI, Menu_Size, 0, Mono_Frame.Width, Panel_Top + 50,
         "Chapter " & Image (Chapter) & " of " & Image (Chapters)
         & ", page " & Image (Page) & " of " & Image (Pages));

      Draw_Button (Fr, UI, Button_X, "Library");
      Draw_Button (Fr, UI, Button_2_X, "Settings");
   end Draw_Menu;

   function Menu_At (X, Y : Integer) return Menu_Choice is
     (if Y not in Button_Y .. Button_Y + Button_H - 1 then Close
      elsif X in Button_X .. Button_X + Button_W - 1 then Library
      elsif X in Button_2_X .. Button_2_X + Button_W - 1 then Settings
      else Close);

end Reader_View;
