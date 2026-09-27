with Glyph_Cache;
with Text_Raster;
with UTF8;

package body Reader_View
  with SPARK_Mode => On
is
   use type UTF8.Code_Point;

   Soft_Hyphen : constant UTF8.Code_Point := 16#AD#;

   Foot_Size : constant := 20;
   Menu_Size : constant := 26;

   --  The menu panel and its buttons, side by side: Library, Contents
   --  (when the book has a table of contents) and Settings.
   Panel_Top    : constant := Status_Bar.Height;
   Panel_Height : constant := 190;
   Button_X     : constant := 20;
   Button_Gap   : constant := 16;
   Button_Y     : constant := Panel_Top + 90;
   Button_H     : constant := 70;

   subtype Button_Count is Positive range 2 .. 3;

   function Button_W (N : Button_Count) return Positive is
     ((Mono_Frame.Width - 2 * Button_X - (N - 1) * Button_Gap) / N);

   --  The left edge of button K (0-based) of N.
   function Button_Left (K : Natural; N : Button_Count) return Natural is
     (Button_X + K * (Button_W (N) + Button_Gap))
     with Pre  => K < N,
          Post => Button_Left'Result + Button_W (N) <= Mono_Frame.Width;

   --  Taps above this line open the menu.
   Menu_Band : constant := Status_Bar.Height + 40;

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

   --  One line, with the extra width of a justified line spread over its
   --  spaces (the first Extra mod Spaces spaces get one pixel more), or the
   --  excess of a line set tighter than its natural width taken from them
   --  the same way, and the hyphen of a word broken at its end.  Kerned as
   --  Page_Layout measured it.
   procedure Draw_Line
     (Fr       : in out Mono_Frame.Frame;
      Masks    : in out Mono_Frame.Grey_Masks;
      Grey     : Boolean;
      F        : Truetype.Font;
      T        : Text_Metrics.Table;
      G        : Page_Layout.Geometry;
      Text     : String;
      L        : Page_Layout.Line;
      Baseline : Integer)
     with Pre => Text'First = 1 and then Text'Last < Positive'Last
                 and then L.Last <= Text'Last
                 and then Text_Metrics.Size (T) <= Page_Layout.Max_Size
   is
      use Page_Layout;

      Size    : constant Positive := Text_Metrics.Size (T);
      Gain    : constant Positive :=
        (if Grey then Text_Raster.Grey_Gain_For (Size)
         else Text_Raster.Gain_For (Size));
      Space_W : constant Natural :=
        Text_Metrics.Advance (T, F, Character'Pos (' '));
      Budget  : constant Integer :=
        G.Col_Width - (if L.Indented then G.Indent else 0);
      Extra   : Natural;
      Share   : Natural := 0;
      Rest    : Natural := 0;
      Cut     : Natural := 0;   --  taken from every space
      Cut_Rest : Natural := 0;  --  and one pixel more from the first ones
      X       : Natural := Margin_X + (if L.Indented then G.Indent else 0);
      P       : Positive := L.First;
      C       : UTF8.Code_Point;
      Prev    : UTF8.Code_Point := Text_Metrics.No_Code;
      Gl      : Natural;
      Face    : Truetype.Font;

      --  Draw glyph Id of Fc with its pen at Pen.  The cache's own advance for the
      --  glyph (Adv) is unused on purpose: the pen follows T's advances,
      --  which are what the line was measured with, so a line is drawn
      --  exactly as wide as it was set.
      procedure Glyph_At (Fc : Truetype.Font; Id : Natural; Pen : Integer) is
         Adv : Natural;
         pragma Warnings
           (GNATprove, Off, """Adv"" is set by ""Draw*"" but not used*",
            Reason => "the pen follows the layout's advances, not the cache's");
      begin
         if Grey then
            Glyph_Cache.Draw_Grey
              (Fr, Masks, Fc, Id, Size, Gain, Pen, Baseline, Adv);
         else
            Glyph_Cache.Draw
              (Fr, Fc, Id, Size, Gain, Text_Raster.Ink_Threshold,
               Pen, Baseline, True, Adv);
         end if;
         pragma Warnings
           (GNATprove, On, """Adv"" is set by ""Draw*"" but not used*");
      end Glyph_At;
   begin
      if Justify and then not L.Para_End and then L.Spaces > 0
        and then Budget > L.Width
      then
         Extra := Budget - L.Width;
         --  Extra is at most Max_Px, so a space that wide takes any
         --  stretch (and the product below cannot overflow).
         if Space_W >= Max_Px
           or else Extra / L.Spaces <= Max_Stretch * Space_W
         then
            Share := Extra / L.Spaces;
            Rest := Extra mod L.Spaces;
         end if;
      elsif L.Spaces > 0 and then L.Width > Budget and then Budget >= 0 then
         --  Page_Layout shrinks spaces by at most Shrink_Of each.
         Extra := L.Width - Budget;
         if Extra / L.Spaces < Space_W then
            Cut := Extra / L.Spaces;
            Cut_Rest := Extra mod L.Spaces;
         end if;
      end if;

      while P <= L.Last loop
         pragma Loop_Invariant (P >= L.First);
         pragma Loop_Variant (Increases => P);
         if Text (P) = ' ' then
            X := Add_Sat (Add_Sat (X, Space_W), Share);
            if Rest > 0 then
               X := Add_Sat (X, 1);
               Rest := Rest - 1;
            end if;
            X := Natural'Max (0, X - Cut);
            if Cut_Rest > 0 then
               X := Natural'Max (0, X - 1);
               Cut_Rest := Cut_Rest - 1;
            end if;
            Prev := Text_Metrics.No_Code;
            P := P + 1;
         else
            UTF8.Next_Code (Text, P, C);
            --  A soft hyphen is invisible and does not break the kerning.
            if C /= Soft_Hyphen then
               X := Add_Kern (X, Text_Metrics.Kern (T, Prev, C));
               Prev := C;
            end if;
            Text_Metrics.Find (T, F, C, Face, Gl);
            if Gl /= 0 then
               Glyph_At (Face, Gl, X);
            end if;
            X := Add_Sat (X, Text_Metrics.Advance (T, F, C));
         end if;
      end loop;

      if L.Hyphen then
         X := Add_Kern (X, Text_Metrics.Kern (T, Prev, Character'Pos ('-')));
         Text_Metrics.Find (T, F, Character'Pos ('-'), Face, Gl);
         if Gl /= 0 then
            Glyph_At (Face, Gl, X);
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
     (Fr    : out Mono_Frame.Frame;
      Masks : out Mono_Frame.Grey_Masks;
      Grey  : Boolean;
      UI    : Truetype.Font;
      F     : Truetype.Font;
      T     : Text_Metrics.Table;
      G     : Page_Layout.Geometry;
      Text  : String;
      Start : Positive;
      W     : in out Page_Layout.Workspace;
      Title : String;
      Batt  : Status_Bar.Battery;
      Page, Pages : Natural)
   is
      --  Drawing sets the page again the way Paginate did, so the two can
      --  never disagree.
      N : Positive;
      Y : Natural := Text_Top;
      L : Page_Layout.Line;
   begin
      Page_Layout.Page_Lines (T, F, G, Text, Start, W, N);
      Mono_Frame.Clear (Fr);
      Mono_Frame.Clear (Masks);
      Status_Bar.Draw (Fr, UI, Title, Batt);
      for I in 1 .. N loop
         L := W.Lines (I);
         if L.Last <= Text'Last then
            Draw_Line (Fr, Masks, Grey, F, T, G, Text, L,
                       Page_Layout.Add_Sat (Y, G.Ascent));
         end if;
         --  The page stops before the lines leave the area, but that is
         --  not visible from here: add saturating.
         Y := Page_Layout.Add_Sat
           (Y, G.Line_Height + (if L.Para_End then G.Para_Gap else 0));
      end loop;
      Draw_Footer (Fr, UI, Page, Pages);
   end Draw_Page;

   procedure Draw_Message
     (Fr      : out Mono_Frame.Frame;
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
     (Fr : in out Mono_Frame.Frame; UI : Truetype.Font; K : Natural;
      N : Button_Count; Label : String)
     with Pre => K < N and then Label'Last < Positive'Last
   is
      Asc  : constant Natural := Text_Raster.Ascent_Px (UI, Menu_Size);
      Desc : constant Natural := Text_Raster.Descent_Px (UI, Menu_Size);
      X    : constant Natural := Button_Left (K, N);
      W    : constant Positive := Button_W (N);
   begin
      Mono_Frame.Frame_Rect (Fr, X, Button_Y, W, Button_H);
      Mono_Frame.Frame_Rect (Fr, X + 1, Button_Y + 1, W - 2, Button_H - 2);
      Text_Raster.Draw_Centered
        (Fr, UI, Menu_Size, X, X + W,
         Button_Y + (Button_H + Asc - Desc) / 2, Label);
   end Draw_Button;

   procedure Draw_Menu
     (Fr                : in out Mono_Frame.Frame;
      UI                : Truetype.Font;
      Chapter, Chapters : Natural;
      Page, Pages       : Natural;
      Has_Contents      : Boolean)
   is
      N : constant Button_Count := (if Has_Contents then 3 else 2);
   begin
      Mono_Frame.Fill_Rect
        (Fr, 0, Panel_Top, Mono_Frame.Width, Panel_Height, Black => False);
      Mono_Frame.Fill_Rect
        (Fr, 0, Panel_Top + Panel_Height - 3, Mono_Frame.Width, 3);

      Text_Raster.Draw_Centered
        (Fr, UI, Menu_Size, 0, Mono_Frame.Width, Panel_Top + 50,
         "Chapter " & Image (Chapter) & " of " & Image (Chapters)
         & ", page " & Image (Page) & " of " & Image (Pages));

      Draw_Button (Fr, UI, 0, N, "Library");
      if Has_Contents then
         Draw_Button (Fr, UI, 1, N, "Contents");
      end if;
      Draw_Button (Fr, UI, N - 1, N, "Settings");
   end Draw_Menu;

   function Menu_At
     (X, Y : Integer; Has_Contents : Boolean) return Menu_Choice
   is
      N : constant Button_Count := (if Has_Contents then 3 else 2);
   begin
      if Y not in Button_Y .. Button_Y + Button_H - 1 then
         return Close;
      end if;
      for K in 0 .. N - 1 loop
         if X in Button_Left (K, N) .. Button_Left (K, N) + Button_W (N) - 1
         then
            return (if K = 0 then Library
                    elsif K = N - 1 then Settings
                    else Contents);
         end if;
      end loop;
      return Close;
   end Menu_At;

end Reader_View;
