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
      else -1);

   Soft_Hyphen : constant UTF8.Code_Point := 16#AD#;

   function Is_Space_Like (C : UTF8.Code_Point) return Boolean is
     (C = 16#A0# or else C in 16#2000# .. 16#200A# or else C = 16#202F#);

   function Code_Of (S : Slot) return UTF8.Code_Point is
     (if S <= Latin_Last then UTF8.Code_Point (S)
      elsif S < Punct_Base
      then UTF8.Code_Point (S - Greek_Base) + Greek_First
      else UTF8.Code_Point (S - Punct_Base) + Punct_First);

   procedure Prepare (T : out Table; F : Truetype.Font; Size : Positive) is
      Space : constant Natural := Truetype.Glyph_Index (F, 32);
      C     : UTF8.Code_Point;
      G     : Natural;
   begin
      T.Size := Size;
      for S in Slot loop
         C := Code_Of (S);
         G := Truetype.Glyph_Index (F, Unsigned_32 (C));
         if G = 0 and then Is_Space_Like (C) then
            G := Space;
         elsif C = Soft_Hyphen then
            G := 0;   --  invisible; the layout draws a hyphen where it breaks
         end if;
         T.Entries (S) :=
           (Glyph   => G,
            Advance =>
              (if G = 0 then 0 else Truetype.Raster.Advance_Px (F, G, Size)));
      end loop;
   end Prepare;

   function Glyph
     (T : Table; F : Truetype.Font; C : UTF8.Code_Point) return Natural
   is
      S : constant Integer := Slot_Of (C);
   begin
      if S >= 0 then
         return T.Entries (S).Glyph;
      else
         return Truetype.Glyph_Index (F, Unsigned_32 (C));
      end if;
   end Glyph;

   function Advance
     (T : Table; F : Truetype.Font; C : UTF8.Code_Point) return Natural
   is
      S : constant Integer := Slot_Of (C);
      G : Natural;
   begin
      if S >= 0 then
         return T.Entries (S).Advance;
      end if;
      G := Truetype.Glyph_Index (F, Unsigned_32 (C));
      return (if G = 0 then 0 else Truetype.Raster.Advance_Px (F, G, T.Size));
   end Advance;

end Text_Metrics;
