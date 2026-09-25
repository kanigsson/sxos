package X4_Display is
   --  Draw in 480x800 portrait coordinates, then submit one full refresh.
   procedure Initialize;
   procedure Clear;

   --  Black filled rectangle in portrait coordinates, clipped to the panel.
   --  Used as the highlight bar behind the selected list entry.
   procedure Fill_Rect (X, Y, W, H : Natural);

   --  Inverted plots the glyphs in white (text on a Fill_Rect bar) instead
   --  of the normal black-on-white.
   procedure Draw_Line (X, Y : Natural; Text : String; Inverted : Boolean := False);
   procedure Show;
end X4_Display;
