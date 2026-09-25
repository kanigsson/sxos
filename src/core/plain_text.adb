with Interfaces; use Interfaces;
with UTF8;

package body Plain_Text
  with SPARK_Mode => On
is
   use type UTF8.Code_Point;

   --  Windows-1252's 0x80 .. 0x9F; 0 marks the five undefined bytes.
   type CP1252_Table is array (Bytes.Byte range 16#80# .. 16#9F#)
     of UTF8.Code_Point;
   CP1252 : constant CP1252_Table :=
     (16#20AC#, 0, 16#201A#, 16#0192#, 16#201E#, 16#2026#, 16#2020#, 16#2021#,
      16#02C6#, 16#2030#, 16#0160#, 16#2039#, 16#0152#, 0, 16#017D#, 0,
      0, 16#2018#, 16#2019#, 16#201C#, 16#201D#, 16#2022#, 16#2013#, 16#2014#,
      16#02DC#, 16#2122#, 16#0161#, 16#203A#, 16#0153#, 0, 16#017E#, 16#0178#);

   function Decode_1252 (B : Bytes.Byte) return UTF8.Code_Point is
     (if B < 16#80# or else B >= 16#A0# then UTF8.Code_Point (B)
      elsif CP1252 (B) = 0 then UTF8.Replacement
      else CP1252 (B));

   --  Is Input well-formed UTF-8 (no overlongs, surrogates or values past
   --  U+10FFFF)?
   function Is_UTF8 (Input : Bytes.Byte_Array) return Boolean is
      P    : Natural;
      B    : Bytes.Byte;
      More : Natural;
      Lo, Hi : Bytes.Byte;
   begin
      if Input'Length = 0 then
         return True;
      end if;
      P := Input'First;
      while P <= Input'Last loop
         pragma Loop_Invariant (P >= Input'First);
         pragma Loop_Variant (Increases => P);
         B := Input (P);
         Lo := 16#80#;
         Hi := 16#BF#;
         if B < 16#80# then
            More := 0;
         elsif B in 16#C2# .. 16#DF# then
            More := 1;
         elsif B in 16#E0# .. 16#EF# then
            More := 2;
            if B = 16#E0# then
               Lo := 16#A0#;
            elsif B = 16#ED# then
               Hi := 16#9F#;
            end if;
         elsif B in 16#F0# .. 16#F4# then
            More := 3;
            if B = 16#F0# then
               Lo := 16#90#;
            elsif B = 16#F4# then
               Hi := 16#8F#;
            end if;
         else
            return False;
         end if;
         if Input'Last - P < More then
            return False;
         end if;
         for K in 1 .. More loop
            if Input (P + K) not in (if K = 1 then Lo else 16#80#)
                                  .. (if K = 1 then Hi else 16#BF#)
            then
               return False;
            end if;
         end loop;
         exit when Input'Last - P <= More;
         P := P + More + 1;
      end loop;
      return True;
   end Is_UTF8;

   function Output_Bound (Input : Bytes.Byte_Array) return Natural is
      N : Natural := 0;
   begin
      if Input'Length = 0 then
         return 0;
      elsif Is_UTF8 (Input) then
         --  Input'Length, except for the one array too long to count in a
         --  Natural.
         return (if Input'Last - Input'First < Natural'Last
                 then Input'Last - Input'First + 1 else Natural'Last);
      end if;
      for B of Input loop
         exit when N > Natural'Last - 3;
         N := N + UTF8.Encoded_Length (Decode_1252 (B));
      end loop;
      return N;
   end Output_Bound;

   --  Hard-wrapped text keeps its lines shorter than this.
   Wrap_Width : constant := 100;

   procedure Normalize
     (Input  : Bytes.Byte_Array;
      Output : out String;
      Last   : out Natural)
   is
      Valid         : constant Boolean := Is_UTF8 (Input);
      Text_Lines    : Natural := 0;   --  lines with something on them
      Long_Lines    : Natural := 0;   --  ... of more than Wrap_Width bytes
      Blanks        : Natural := 0;
      Line_Length   : Natural := 0;
      Line_Empty    : Boolean := True;
      Blank_Mode    : Boolean;
      Pending_Space : Boolean := False;
      Pending_Break : Boolean := False;
      P             : Natural;
      B             : Bytes.Byte;

      procedure Emit_Separator is
      begin
         if Last > 0 and then Last < Output'Last then
            if Pending_Break then
               Last := Last + 1;
               Output (Last) := Paragraph_Break;
            elsif Pending_Space then
               Last := Last + 1;
               Output (Last) := ' ';
            end if;
         end if;
         Pending_Break := False;
         Pending_Space := False;
      end Emit_Separator;

   begin
      Output := (others => ' ');
      Last := 0;
      if Input'Length = 0 then
         return;
      end if;
      P := Input'First;

      --  Count blank, text and long lines to pick the paragraph convention.
      for C of Input loop
         if C = 10 then
            if Line_Empty then
               Blanks := (if Blanks < Natural'Last then Blanks + 1 else Blanks);
            else
               Text_Lines := (if Text_Lines < Natural'Last then Text_Lines + 1
                              else Text_Lines);
               if Line_Length > Wrap_Width and then Long_Lines < Natural'Last
               then
                  Long_Lines := Long_Lines + 1;
               end if;
            end if;
            Line_Empty := True;
            Line_Length := 0;
         else
            Line_Length := (if Line_Length < Natural'Last then Line_Length + 1
                            else Line_Length);
            if C /= 32 and then C /= 9 and then C /= 13 then
               Line_Empty := False;
            end if;
         end if;
      end loop;
      Blank_Mode := Blanks > 0 and then Long_Lines < Text_Lines / 10;

      --  Skip a byte-order mark (a file that is nothing else has no text).
      if Valid and then Input'Length >= 3
        and then Input (P) = 16#EF# and then Input (P + 1) = 16#BB#
        and then Input (P + 2) = 16#BF#
      then
         if Input'Last - P = 2 then
            return;
         end if;
         P := P + 3;
      end if;

      Line_Empty := True;
      while P <= Input'Last and then Last < Output'Last loop
         pragma Loop_Invariant (P >= Input'First and then Last <= Output'Last);
         B := Input (P);
         if B = 10 then
            if Line_Empty then
               Pending_Break := True;          --  a blank line
            elsif Blank_Mode then
               Pending_Space := True;          --  a wrapped line continues
            else
               Pending_Break := True;          --  one line, one paragraph
            end if;
            Line_Empty := True;
         elsif B = 32 or else B = 9 or else B = 13 then
            Pending_Space := True;
         else
            Emit_Separator;
            Line_Empty := False;
            if Valid and then Last < Output'Last then
               Last := Last + 1;
               Output (Last) := Character'Val (B);
            elsif not Valid then
               UTF8.Append (Output, Last, Decode_1252 (B));
            end if;
         end if;
         exit when P = Input'Last;
         P := P + 1;
      end loop;
   end Normalize;

   function Section_End
     (Text : String; From : Positive; Target : Positive) return Positive
   is
      Soft : Natural;
      Hard : Natural;
      E    : Natural;
   begin
      if Text'Last - From < Target then
         return Text'Last;
      end if;
      Soft := From + Target - 1;
      Hard := (if Text'Last - Soft > Target then Soft + Target else Text'Last);
      for K in Soft .. Hard loop
         if Text (K) = Paragraph_Break then
            return K;
         end if;
      end loop;
      for K in reverse From .. Soft loop
         if Text (K) = ' ' then
            return K;
         end if;
      end loop;
      --  Back up to the end of a character: the next byte must not be a
      --  UTF-8 continuation byte.
      E := Soft;
      while E > From
        and then Character'Pos (Text (E + 1)) in 16#80# .. 16#BF#
      loop
         pragma Loop_Invariant (E in From .. Soft);
         pragma Loop_Variant (Decreases => E);
         E := E - 1;
      end loop;
      return E;
   end Section_End;
end Plain_Text;
