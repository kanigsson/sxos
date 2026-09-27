with Interfaces; use Interfaces;

with Fallback;
with Glyph_Cache;
with Truetype.Raster;
with UTF8;

package body Text_Raster
  with SPARK_Mode => On
is

   package TR renames Truetype.Raster;

   --  Font units -> pixels at Size, rounded up.  In 64 bits, and saturating
   --  at Natural'Last, which only an absurd size reaches.  Units is at most
   --  the span of three 16-bit metrics.
   Max_Units : constant := 3 * 32_768;

   function Px (F : Truetype.Font; Units : Natural; Size : Positive)
     return Natural
   is (Natural
         (Long_Long_Integer'Min
            (Long_Long_Integer (Natural'Last),
             (Long_Long_Integer (Units) * Long_Long_Integer (Size)
              + Long_Long_Integer (Truetype.Units_Per_Em (F)) - 1)
             / Long_Long_Integer (Truetype.Units_Per_Em (F)))))
   with Pre  => Units <= Max_Units,
        Post => (if Size <= 1024 then Px'Result <= 2**27);

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

   --  Total + A, saturating: a width past Natural'Last is off any frame.
   function Add_Sat (Total, A : Natural) return Natural is
     (if A > Natural'Last - Total then Natural'Last else Total + A);

   --  Total moved by a kerning adjustment K, clamped to 0 and saturating.
   function Add_Kern (Total : Natural; K : Integer) return Natural is
     (if K >= 0 then Add_Sat (Total, K) else Natural'Max (0, Total + K));

   --  The kerning of glyphs Left then Right at Size, in whole pixels
   --  (rounded to nearest).  At most a 16-bit value scaled by Size.
   function Kern_Px
     (F : Truetype.Font; Left, Right : Natural; Size : Positive)
      return Integer
     with Post => Kern_Px'Result in -2**20 .. 2**20
   is
      Units  : constant Integer := Truetype.Kerning (F, Left, Right);
      Scaled : constant Long_Long_Integer :=
        Long_Long_Integer (Units) * Long_Long_Integer (Size);
      Upem   : constant Long_Long_Integer :=
        Long_Long_Integer (Truetype.Units_Per_Em (F));
      R      : constant Long_Long_Integer :=
        (if Scaled >= 0 then (Scaled + Upem / 2) / Upem
         else -((Upem / 2 - Scaled) / Upem));
   begin
      return Integer (Long_Long_Integer'Max
                        (-2**20, Long_Long_Integer'Min (2**20, R)));
   end Kern_Px;

   --  Kern_Px for glyph Left of LF then Right of RF: glyphs of two faces
   --  (one of them the fallback) are not kerned.
   function Kern_Between
     (LF : Truetype.Font; Left : Natural; RF : Truetype.Font; Right : Natural;
      Size : Positive) return Integer
   is (if Left /= 0 and then Truetype."=" (LF, RF)
       then Kern_Px (RF, Left, Right, Size) else 0)
     with Post => Kern_Between'Result in -2**20 .. 2**20;

   -----------
   -- Width --
   -----------

   function Width (F : Truetype.Font; Size : Positive; Str : String)
     return Natural
   is
      Total : Natural := 0;
      --  The Max only matters for a null Str, which the loop skips.
      P     : Positive := Positive'Max (1, Str'First);
      C     : UTF8.Code_Point;
      G     : Natural;
      Fc    : Truetype.Font;
      Prev  : Natural := 0;
      Prev_F : Truetype.Font := F;
   begin
      while P <= Str'Last loop
         pragma Loop_Invariant (P >= Str'First);
         pragma Loop_Variant (Increases => P);
         UTF8.Next_Code (Str, P, C);
         Fallback.Find (F, C, Fc, G);
         if G /= 0 then
            Total := Add_Sat (Add_Kern (Total, Kern_Between
                                          (Prev_F, Prev, Fc, G, Size)),
                              TR.Advance_Px (Fc, G, Size));
            Prev := G;
            Prev_F := Fc;
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
      P   : Positive := Positive'Max (1, Str'First);
      C   : UTF8.Code_Point;
      G   : Natural;
      Fc  : Truetype.Font;
      Adv : Natural;
      K   : Integer;
      Prev : Natural := 0;
      Prev_F : Truetype.Font := F;

      G_Eff : constant Positive :=
        (if Gain = Auto_Gain then Gain_For (Size) else Gain);
   begin
      while P <= Str'Last loop
         pragma Loop_Invariant (P >= Str'First);
         UTF8.Next_Code (Str, P, C);
         Fallback.Find (F, C, Fc, G);
         if G /= 0 then
            --  A pen this far out draws nothing any more: stop.
            exit when Pen > Integer'Last / 2 or else Pen < Integer'First / 2;
            K := Kern_Between (Prev_F, Prev, Fc, G, Size);
            Pen := Pen + K;
            Prev := G;
            Prev_F := Fc;
            Glyph_Cache.Draw
              (Fr, Fc, G, Size, G_Eff, Ink_Threshold, Pen, Baseline, Black, Adv);
            --  A pen past Integer'Last is past any frame: nothing further
            --  could be seen.
            exit when Pen > 0 and then Adv > Integer'Last - Pen;
            Pen := Pen + Adv;
         end if;
      end loop;
   end Draw_Text;

   --  V as an Integer pen position, clamped.  A clamped pen is still more
   --  than Integer'Last - Natural'Last pixels off the frame, so what is
   --  drawn does not change.
   function Clamp (V : Long_Long_Integer) return Integer is
     (Integer (Long_Long_Integer'Max
                 (Long_Long_Integer (Integer'First),
                  Long_Long_Integer'Min (Long_Long_Integer (Integer'Last), V))));

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
        (Fr, F, Size,
         Clamp (Long_Long_Integer (Left)
                + (Long_Long_Integer (Right) - Long_Long_Integer (Left)
                   - Long_Long_Integer (Width (F, Size, Str))) / 2),
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
      Draw_Text
        (Fr, F, Size,
         Clamp (Long_Long_Integer (X) - Long_Long_Integer (Width (F, Size, Str))),
         Baseline, Str, Black, Gain);
   end Draw_Right;

   ---------
   -- Fit --
   ---------

   function Fit (F : Truetype.Font; Size : Positive; Str : String;
                 Max_W : Natural) return Natural
   is
      Last  : Natural := (if Str'First >= 1 then Str'First - 1 else 0);
      Total : Natural := 0;
      P     : Positive := Positive'Max (1, Str'First);
      C     : UTF8.Code_Point;
      G     : Natural;
      Fc    : Truetype.Font;
      Prev  : Natural := 0;
      Prev_F : Truetype.Font := F;
   begin
      while P <= Str'Last loop
         pragma Loop_Invariant
           (P >= Str'First and then Str'First >= 1
            and then Last in Str'First - 1 .. P - 1);
         pragma Loop_Variant (Increases => P);
         UTF8.Next_Code (Str, P, C);
         Fallback.Find (F, C, Fc, G);
         if G /= 0 then
            Total := Add_Sat (Add_Kern (Total, Kern_Between
                                          (Prev_F, Prev, Fc, G, Size)),
                              TR.Advance_Px (Fc, G, Size));
            Prev := G;
            Prev_F := Fc;
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
      if First < Str'First then
         First := Str'First;
      end if;
      while First <= Str'Last and then Str (First) = ' ' loop
         pragma Loop_Invariant (First >= From and then First >= Str'First);
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
         pragma Loop_Invariant
           (Cur in First .. Str'Last + 1 and then Last in First - 1 .. Cur - 1);
         Sp := 0;
         for I in Cur .. Str'Last loop
            pragma Loop_Invariant (Sp = 0);
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
               --  Only how far Q advances matters here, not the code point.
               pragma Warnings
                 (GNATprove, Off, """C"" is set by ""Next_Code"" but not used after the call",
                  Reason => "only the advance of Q is wanted");
               UTF8.Next_Code (Str, Q, C);
               pragma Warnings
                 (GNATprove, On, """C"" is set by ""Next_Code"" but not used after the call");
               Last := Q - 1;
            end if;
         end;
      end if;

      --  Continue past the break, eating the spaces that caused it.
      Next := Last + 1;
      while Next <= Str'Last and then Str (Next) = ' ' loop
         pragma Loop_Invariant (Next > Last);
         Next := Next + 1;
      end loop;
   end Wrap_Line;

end Text_Raster;
