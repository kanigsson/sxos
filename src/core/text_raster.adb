with Interfaces; use Interfaces;

with Glyph_Cache;
with Truetype.Raster;
with UTF8;

package body Text_Raster
  with SPARK_Mode => On
is

   package TR renames Truetype.Raster;

   --  Font units -> pixels at Size, rounded up.
   function Px (F : Truetype.Font; Units : Natural; Size : Positive)
     return Natural
   is ((Units * Size + Truetype.Units_Per_Em (F) - 1)
       / Truetype.Units_Per_Em (F));

   function Ascent_Px (F : Truetype.Font; Size : Positive) return Natural is
     (Px (F, Integer'Max (0, Truetype.Ascent (F)), Size));

   function Descent_Px (F : Truetype.Font; Size : Positive) return Natural is
     (Px (F, Integer'Max (0, -Truetype.Descent (F)), Size));

   function Line_Height_Px (F : Truetype.Font; Size : Positive)
     return Positive
   is
     (Integer'Max
        (1, Px (F, Integer'Max (0, Truetype.Ascent (F) - Truetype.Descent (F)
                                   + Truetype.Line_Gap (F)), Size)));

   -----------
   -- Width --
   -----------

   function Width (F : Truetype.Font; Size : Positive; Str : String)
     return Natural
   is
      Total : Natural := 0;
      P     : Positive := Str'First;
      C     : UTF8.Code_Point;
      G     : Natural;
   begin
      while P <= Str'Last loop
         UTF8.Next_Code (Str, P, C);
         G := Truetype.Glyph_Index (F, Unsigned_32 (C));
         if G /= 0 then
            Total := Total + TR.Advance_Px (F, G, Size);
         end if;
      end loop;
      return Total;
   end Width;

   ---------------
   -- Draw_Text --
   ---------------

   procedure Draw_Text
     (Fr       : in out Mono_Frame.Frame;
      F        : Truetype.Font;
      Size     : Positive;
      X        : Integer;
      Baseline : Integer;
      Str      : String;
      Black    : Boolean := True;
      Gain     : Natural := Auto_Gain)
   is
      Pen : Integer := X;
      P   : Positive := Str'First;
      C   : UTF8.Code_Point;
      G   : Natural;
      Adv : Natural;

      G_Eff : constant Positive :=
        (if Gain = Auto_Gain then Gain_For (Size) else Gain);
   begin
      while P <= Str'Last loop
         UTF8.Next_Code (Str, P, C);
         G := Truetype.Glyph_Index (F, Unsigned_32 (C));
         if G /= 0 then
            Glyph_Cache.Draw
              (Fr, F, G, Size, G_Eff, Ink_Threshold, Pen, Baseline, Black, Adv);
            Pen := Pen + Adv;
         end if;
      end loop;
   end Draw_Text;

   procedure Draw_Centered
     (Fr          : in out Mono_Frame.Frame;
      F           : Truetype.Font;
      Size        : Positive;
      Left, Right : Integer;
      Baseline    : Integer;
      Str         : String;
      Black       : Boolean := True;
      Gain        : Natural := Auto_Gain) is
   begin
      Draw_Text
        (Fr, F, Size, Left + (Right - Left - Width (F, Size, Str)) / 2,
         Baseline, Str, Black, Gain);
   end Draw_Centered;

   procedure Draw_Right
     (Fr       : in out Mono_Frame.Frame;
      F        : Truetype.Font;
      Size     : Positive;
      X        : Integer;
      Baseline : Integer;
      Str      : String;
      Black    : Boolean := True;
      Gain     : Natural := Auto_Gain) is
   begin
      Draw_Text (Fr, F, Size, X - Width (F, Size, Str), Baseline, Str,
                 Black, Gain);
   end Draw_Right;

   ---------
   -- Fit --
   ---------

   function Fit (F : Truetype.Font; Size : Positive; Str : String;
                 Max_W : Natural) return Natural
   is
      Last  : Natural := Str'First - 1;
      Total : Natural := 0;
      P     : Positive := Str'First;
      C     : UTF8.Code_Point;
      G     : Natural;
   begin
      while P <= Str'Last loop
         UTF8.Next_Code (Str, P, C);
         G := Truetype.Glyph_Index (F, Unsigned_32 (C));
         if G /= 0 then
            Total := Total + TR.Advance_Px (F, G, Size);
         end if;
         exit when Total > Max_W;
         Last := P - 1;
      end loop;
      return Last;
   end Fit;

   ---------------
   -- Wrap_Line --
   ---------------

   procedure Wrap_Line
     (F     : Truetype.Font;
      Size  : Positive;
      Str   : String;
      From  : Positive;
      Max_W : Natural;
      First : out Positive;
      Last  : out Natural;
      Next  : out Positive)
   is
      Cur : Positive;
      Sp  : Natural;
      End_Of_Word : Natural;
   begin
      First := From;
      while First <= Str'Last and then Str (First) = ' ' loop
         First := First + 1;
      end loop;

      Last := First - 1;
      Next := First;

      if First > Str'Last then
         return;
      end if;

      --  Extend a word at a time for as long as the measured run fits.
      Cur := First;
      loop
         Sp := 0;
         for I in Cur .. Str'Last loop
            if Str (I) = ' ' then
               Sp := I;
               exit;
            end if;
         end loop;

         End_Of_Word := (if Sp = 0 then Str'Last else Sp - 1);
         exit when End_Of_Word < First;
         exit when Width (F, Size, Str (First .. End_Of_Word)) > Max_W;

         Last := End_Of_Word;
         exit when Sp = 0;
         Cur := Sp + 1;
      end loop;

      --  The first word alone overruns the column: break it by code point,
      --  always placing at least one so the caller makes progress.
      if Last < First then
         declare
            Fits : constant Natural :=
              Fit (F, Size, Str (First .. Str'Last), Max_W);
            Q    : Positive := First;
            C    : UTF8.Code_Point;
         begin
            if Fits >= First then
               Last := Fits;
            else
               UTF8.Next_Code (Str, Q, C);
               Last := Q - 1;
            end if;
         end;
      end if;

      --  Continue past the break, eating the spaces that caused it.
      Next := Last + 1;
      while Next <= Str'Last and then Str (Next) = ' ' loop
         Next := Next + 1;
      end loop;
   end Wrap_Line;

end Text_Raster;
