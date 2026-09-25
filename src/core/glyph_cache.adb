with Interfaces; use Interfaces;

with Truetype.Raster;

--  Not SPARK: the pool and the table are allocated on the heap.
package body Glyph_Cache
  with SPARK_Mode => Off,
       Refined_State => (State => (Pool, Table, Used, Count, Cov,
                                   Cached_Font, Have_Font))
is
   package TR renames Truetype.Raster;
   use type Truetype.Font;

   --  Enough for the glyphs of several sizes of a Latin face: a 30 px
   --  glyph takes about 100 bytes.
   Pool_Size : constant := 256 * 1024;
   Slots     : constant := 2048;              --  a power of two
   Max_Count : constant := Slots * 3 / 4;     --  keep probe chains short

   type Byte_Array is array (Natural range <>) of Unsigned_8;
   type Pool_Access is access Byte_Array;

   type Entry_Type is record
      Used     : Boolean := False;
      G        : Natural := 0;
      Size     : Positive := 1;
      Gain     : Positive := 1;
      W, H     : Natural := 0;
      X_Off    : Integer := 0;
      Y_Off    : Integer := 0;
      Adv      : Natural := 0;
      Offset   : Natural := 0;   --  first byte of the bitmap in Pool
   end record;

   type Entry_Array is array (0 .. Slots - 1) of Entry_Type;
   type Table_Access is access Entry_Array;

   Pool  : constant Pool_Access := new Byte_Array (0 .. Pool_Size - 1);
   Table : constant Table_Access := new Entry_Array;
   Used  : Natural := 0;   --  bytes of Pool in use
   Count : Natural := 0;   --  entries in use

   --  Scratch coverage for the one glyph being rendered; 128 x 128 covers
   --  glyphs up to about 110 px.
   Cell : constant := 128;
   Cov  : TR.Coverage_Array (0 .. Cell * Cell - 1);

   Cached_Font : Truetype.Font;
   Have_Font   : Boolean := False;

   procedure Reset is
   begin
      --  A loop, not an aggregate: GNAT may build an aggregate of the
      --  whole table as a temporary on the (64 KB) stack.
      for E of Table.all loop
         E.Used := False;
      end loop;
      Used := 0;
      Count := 0;
   end Reset;

   function Hash (G, Size, Gain : Natural) return Natural is
      H : constant Unsigned_32 :=
        Unsigned_32 (G) * 2654435761
        xor Unsigned_32 (Size) * 40503
        xor Unsigned_32 (Gain) * 97;
   begin
      return Natural (Shift_Right (H, 8) and (Slots - 1));
   end Hash;

   --  Rasterise glyph G into slot S.
   procedure Fill (S : Natural; F : Truetype.Font; G : Natural;
                   Size, Gain, Threshold : Natural)
   is
      W, H, Adv : Natural;
      XO, YO    : Integer;
      Ok        : Boolean;
      Stride    : Natural;
   begin
      TR.Render (F, G, Size, W, H, XO, YO, Adv, Cov, Ok, Gain => Gain);
      if not Ok then
         W := 0;
         H := 0;
         Adv := TR.Advance_Px (F, G, Size);
      end if;
      Stride := (W + 7) / 8;
      Table (S) := (Used => True, G => G, Size => Size, Gain => Gain,
                    W => W, H => H, X_Off => XO, Y_Off => YO, Adv => Adv,
                    Offset => Used);
      for Row in 0 .. H - 1 loop
         for B in 0 .. Stride - 1 loop
            declare
               Bits : Unsigned_8 := 0;
            begin
               for K in 0 .. 7 loop
                  if B * 8 + K < W
                    and then Natural (Cov (Row * W + B * 8 + K)) >= Threshold
                  then
                     Bits := Bits or Shift_Right (Unsigned_8'(16#80#), K);
                  end if;
               end loop;
               Pool (Used + Row * Stride + B) := Bits;
            end;
         end loop;
      end loop;
      Used := Used + Stride * H;
      Count := Count + 1;
   end Fill;

   procedure Draw
     (Fr        : in out Mono_Frame.Frame;
      F         : Truetype.Font;
      G         : Natural;
      Size      : Positive;
      Gain      : Positive;
      Threshold : Natural;
      X         : Integer;
      Baseline  : Integer;
      Black     : Boolean;
      Adv       : out Natural)
   is
      S : Natural;
   begin
      if not Have_Font or else Cached_Font /= F then
         Reset;
         Cached_Font := F;
         Have_Font := True;
      end if;

      S := Hash (G, Size, Gain);
      while Table (S).Used
        and then not (Table (S).G = G and then Table (S).Size = Size
                      and then Table (S).Gain = Gain)
      loop
         S := (S + 1) mod Slots;
      end loop;

      if not Table (S).Used then
         --  The largest glyph the scratch cell holds needs Cell * Cell / 8.
         if Count >= Max_Count or else Used + Cell * Cell / 8 > Pool_Size then
            Reset;
            S := Hash (G, Size, Gain);
         end if;
         Fill (S, F, G, Size, Gain, Threshold);
      end if;

      declare
         E      : Entry_Type renames Table (S);
         Stride : constant Natural := (E.W + 7) / 8;
         Left   : constant Integer := X + E.X_Off;
         Top    : constant Integer := Baseline + E.Y_Off;
         Bits   : Unsigned_8;
      begin
         for Row in 0 .. E.H - 1 loop
            for B in 0 .. Stride - 1 loop
               Bits := Pool (E.Offset + Row * Stride + B);
               if Bits /= 0 then
                  for K in 0 .. 7 loop
                     if (Bits and Shift_Right (Unsigned_8'(16#80#), K)) /= 0
                     then
                        Mono_Frame.Plot (Fr, Left + B * 8 + K, Top + Row, Black);
                     end if;
                  end loop;
               end if;
            end loop;
         end loop;
         Adv := E.Adv;
      end;
   end Draw;

end Glyph_Cache;
