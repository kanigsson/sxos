with Interfaces; use Interfaces;
with X4_Font;

package body Bitmap_Text
  with SPARK_Mode => On
is

   procedure Draw
     (F     : in out Mono_Frame.Frame;
      X, Y  : Integer;
      Text  : String;
      Scale : Positive := 2;
      Black : Boolean := True)
   is
      Pen : Integer := X;
   begin
      --  Nothing to draw below the frame; returning here also keeps
      --  Y + Row * Scale in range.
      if Y >= Mono_Frame.Height then
         return;
      end if;
      for C of Text loop
         exit when Pen >= Mono_Frame.Width;
         for Col in 0 .. 4 loop
            declare
               Bits : constant Unsigned_8 := X4_Font.Column (C, Col);
            begin
               for Row in 0 .. 6 loop
                  if (Bits and Shift_Left (Unsigned_8'(1), Row)) /= 0 then
                     Mono_Frame.Fill_Rect
                       (F, Pen + Col * Scale, Y + Row * Scale, Scale, Scale,
                        Black);
                  end if;
               end loop;
            end;
         end loop;
         Pen := Pen + Char_Width (Scale);
      end loop;
   end Draw;

end Bitmap_Text;
