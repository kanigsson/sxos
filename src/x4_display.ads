package X4_Display is
   --  Draw in 480x800 portrait coordinates, then submit one full refresh.
   procedure Initialize;
   procedure Clear;
   procedure Draw_Line (X, Y : Natural; Text : String);
   procedure Show;
end X4_Display;
