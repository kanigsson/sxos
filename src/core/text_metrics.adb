with Interfaces; use Interfaces;

with Truetype.Raster;

package body Text_Metrics
  with SPARK_Mode => On
is
   use type UTF8.Code_Point;

   --  The table slot of C, or -1 when C is not covered.
   function Slot_Of (C : UTF8.Code_Point) return Integer is
     (if C <= Latin_Last then Integer (C)
      elsif C in Greek_First .. Greek_Last
      then Greek_Base + Integer (C - Greek_First)
      elsif C in Punct_First .. Punct_Last
      then Punct_Base + Integer (C - Punct_First)
      elsif C in CJK_First .. CJK_Last
      then CJK_Base + Integer (C - CJK_First)
      elsif C in Hangul_First .. Hangul_Last
      then Hangul_Base + Integer (C - Hangul_First)
      elsif C in Wide_First .. Wide_Last
      then Wide_Base + Integer (C - Wide_First)
      else -1);

   Soft_Hyphen : constant UTF8.Code_Point := 16#AD#;

   function Is_Space_Like (C : UTF8.Code_Point) return Boolean is
     (C = 16#A0# or else C in 16#2000# .. 16#200A# or else C = 16#202F#);

   function Code_Of (S : Slot) return UTF8.Code_Point is
     (if S <= Latin_Last then UTF8.Code_Point (S)
      elsif S < Punct_Base
      then UTF8.Code_Point (S - Greek_Base) + Greek_First
      elsif S < CJK_Base
      then UTF8.Code_Point (S - Punct_Base) + Punct_First
      elsif S < Hangul_Base
      then UTF8.Code_Point (S - CJK_Base) + CJK_First
      elsif S < Wide_Base
      then UTF8.Code_Point (S - Hangul_Base) + Hangul_First
      else UTF8.Code_Point (S - Wide_Base) + Wide_First);

   --  The kern slot of C, or -1 when C is not kerned.
   function Kern_Slot_Of (C : UTF8.Code_Point) return Integer is
     (if C in 16#21# .. 16#7E# then Integer (C - 16#21#)
      elsif C in Kern_Latin_1 .. 16#17F#
      then Kern_Base_2 + Integer (C - Kern_Latin_1)
      elsif C in Kern_Punct .. 16#2027#
      then Kern_Base_3 + Integer (C - Kern_Punct)
      else -1)
   with Post => Kern_Slot_Of'Result in -1 .. Kern_Slots - 1;

   function Kern_Code (S : Kern_Slot) return UTF8.Code_Point is
     (if S < Kern_Base_2 then UTF8.Code_Point (S) + 16#21#
      elsif S < Kern_Base_3
      then UTF8.Code_Point (S - Kern_Base_2) + Kern_Latin_1
      else UTF8.Code_Point (S - Kern_Base_3) + Kern_Punct);

   --  Font units -> pixels at Size, rounded to nearest, clamped to a byte.
   function Kern_Px (Units : Integer_16; Size : Positive; Upem : Positive)
     return Integer_8
   is
      Scaled : constant Long_Long_Integer :=
        Long_Long_Integer (Units) * Long_Long_Integer (Size);
      Half   : constant Long_Long_Integer := Long_Long_Integer (Upem) / 2;
      R      : constant Long_Long_Integer :=
        (if Scaled >= 0 then (Scaled + Half) / Long_Long_Integer (Upem)
         else -((-Scaled + Half) / Long_Long_Integer (Upem)));
   begin
      return Integer_8 (Long_Long_Integer'Max
                          (-128, Long_Long_Integer'Min (127, R)));
   end Kern_Px;

   --  The glyph for C in F, else in the first face of T's chain that has
   --  it (Source is its place there, 0 for F).
   procedure Look_Up
     (T      : Table;
      F      : Truetype.Font;
      C      : UTF8.Code_Point;
      Source : out Natural;
      G      : out Natural)
     with Post => Source <= T.N_Backups
   is
      use type Truetype.Font;
   begin
      Source := 0;
      G := Truetype.Glyph_Index (F, Unsigned_32 (C));
      for I in 1 .. T.N_Backups loop
         exit when G /= 0;
         if T.Backups (I) /= F then
            G := Truetype.Glyph_Index (T.Backups (I), Unsigned_32 (C));
            if G /= 0 then
               Source := I;
            end if;
         end if;
      end loop;
   end Look_Up;

   function Face_Of
     (T : Table; F : Truetype.Font; Source : Natural) return Truetype.Font
   is (if Source in 1 .. T.N_Backups then T.Backups (Source) else F);

   procedure Prepare (T : in out Table; F : Truetype.Font; Size : Positive) is
      use type Truetype.Font;
      Space : constant Natural := Truetype.Glyph_Index (F, 32);
      C     : UTF8.Code_Point;
      G     : Natural;
      Src   : Natural;
   begin
      T.Size := Size;
      T.N_Backups := Fallback.Count;
      for I in 1 .. T.N_Backups loop
         T.Backups (I) := Fallback.Face (I);
      end loop;
      for S in Slot loop
         C := Code_Of (S);
         if C = Soft_Hyphen then
            G := 0;   --  invisible; the layout draws a hyphen where it breaks
            Src := 0;
         else
            Look_Up (T, F, C, Src, G);
            if G = 0 and then Is_Space_Like (C) then
               G := Space;
            end if;
         end if;
         T.Entries (S) :=
           (Glyph   => G,
            Advance =>
              (if G = 0 then 0
               else Truetype.Raster.Advance_Px (Face_Of (T, F, Src), G, Size)),
            Source  => Src);
      end loop;

      if not T.Kern_Valid or else T.Kern_Face /= F then
         --  Only F's own glyphs: F's kerning knows nothing of the others.
         for S in Kern_Slot loop
            declare
               Sl : constant Integer := Slot_Of (Kern_Code (S));
            begin
               T.Kern_Glyphs (S) :=
                 (if Sl < 0 or else T.Entries (Sl).Source /= 0 then 0
                  else T.Entries (Sl).Glyph);
            end;
         end loop;
         Truetype.Kerning_Matrix (F, T.Kern_Glyphs, T.Kern_Units, T.Settled);
         T.Kern_Face := F;
         T.Kern_Valid := True;
      end if;
      for K in Kern_Index loop
         T.Kern_Px (K) :=
           Kern_Px (T.Kern_Units (K), Size, Truetype.Units_Per_Em (F));
      end loop;
   end Prepare;

   procedure Find
     (T     : Table;
      F     : Truetype.Font;
      C     : UTF8.Code_Point;
      Found : out Truetype.Font;
      G     : out Natural)
   is
      S   : constant Integer := Slot_Of (C);
      Src : Natural;
   begin
      if S >= 0 then
         G := T.Entries (S).Glyph;
         Src := T.Entries (S).Source;
      else
         Look_Up (T, F, C, Src, G);
      end if;
      Found := Face_Of (T, F, Src);
   end Find;

   function Advance
     (T : Table; F : Truetype.Font; C : UTF8.Code_Point) return Natural
   is
      S  : constant Integer := Slot_Of (C);
      Fc : Truetype.Font;
      G  : Natural;
   begin
      if S >= 0 then
         return T.Entries (S).Advance;
      end if;
      Find (T, F, C, Fc, G);
      return (if G = 0 then 0 else Truetype.Raster.Advance_Px (Fc, G, T.Size));
   end Advance;

   function Kern (T : Table; Left, Right : UTF8.Code_Point) return Integer
   is
      L : constant Integer := Kern_Slot_Of (Left);
      R : constant Integer := Kern_Slot_Of (Right);
   begin
      if L < 0 or else R < 0 then
         return 0;
      end if;
      return Integer (T.Kern_Px (L * Kern_Slots + R));
   end Kern;

end Text_Metrics;
