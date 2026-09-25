--  Render one sxos screen from a host directory standing in for the SD card.
--
--    preview_main CARD_DIR library OUT.pgm [SELECTED [BATTERY%]]
--
--  The PGM is portrait 480 x 800, as the device is held.
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Streams.Stream_IO;
with Ada.Text_IO; use Ada.Text_IO;

with Library_View;
with Mono_Frame;
with Shelf;
with Status_Bar;
with Truetype;
with Host_Card;

procedure Preview_Main is
   Screen : Mono_Frame.Frame;
   Books  : Shelf.List;
   Font   : Truetype.Font;
   Data   : Truetype.Data_Ref;
   Ok     : Boolean;
   Batt   : Status_Bar.Battery;
   use type Truetype.Data_Ref;

   procedure Write_PGM (Path : String) is
      use Ada.Streams;
      F      : Stream_IO.File_Type;
      Header : constant String :=
        "P5" & ASCII.LF & "480 800" & ASCII.LF & "255" & ASCII.LF;
      Row    : Stream_Element_Array (1 .. Mono_Frame.Width);
   begin
      Stream_IO.Create (F, Stream_IO.Out_File, Path);
      String'Write (Stream_IO.Stream (F), Header);
      for Y in 0 .. Mono_Frame.Height - 1 loop
         for X in 0 .. Mono_Frame.Width - 1 loop
            Row (Stream_Element_Offset (X + 1)) :=
              (if Mono_Frame.Is_Black (Screen, X, Y) then 0 else 255);
         end loop;
         Stream_IO.Write (F, Row);
      end loop;
      Stream_IO.Close (F);
   end Write_PGM;

begin
   if Argument_Count < 3 then
      Put_Line ("usage: preview_main CARD_DIR library OUT.pgm "
                & "[SELECTED [BATTERY%]]");
      Set_Exit_Status (Failure);
      return;
   end if;

   Data := Host_Card.Load_Font (Argument (1));
   if Data = null then
      Put_Line ("no .ttf in " & Argument (1) & "/Fonts");
      Set_Exit_Status (Failure);
      return;
   end if;
   Truetype.Open (Data, Font, Ok);
   if not Ok then
      Put_Line ("font did not parse");
      Set_Exit_Status (Failure);
      return;
   end if;

   if Argument_Count >= 5 then
      Batt := (Known => True, Level => Natural'Value (Argument (5)),
               Charging => False);
   end if;

   if Argument (2) = "library" then
      Host_Card.Scan_Books (Argument (1), Books);
      Library_View.Draw
        (Screen, Font, Books,
         (if Argument_Count >= 4 then Natural'Value (Argument (4))
          else (if Books.Count > 0 then 1 else 0)),
         Batt);
   else
      Put_Line ("unknown screen " & Argument (2));
      Set_Exit_Status (Failure);
      return;
   end if;

   Write_PGM (Argument (3));
end Preview_Main;
