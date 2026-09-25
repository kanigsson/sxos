with Mono_Frame;

--  The built-in 5x7 ASCII font (X4_Font), scaled up by an integer factor.
--  The fallback for screens that must work with no usable font on the card;
--  everything else goes through Text_Raster.
package Bitmap_Text
  with SPARK_Mode => On
is
   --  Pixel advance of one character at Scale: 5 columns plus 1 of spacing.
   function Char_Width (Scale : Positive) return Positive is (6 * Scale)
     with Pre => Scale <= 64;

   --  Draw Text with its top-left corner at portrait (X, Y).  Characters
   --  outside ' ' .. '~' draw as '?'.  Black => False draws white glyphs, for
   --  text on a filled bar.
   procedure Draw
     (F     : in out Mono_Frame.Frame;
      X, Y  : Integer;
      Text  : String;
      Scale : Positive := 2;
      Black : Boolean := True)
     with Pre => Scale <= 64;

end Bitmap_Text;
