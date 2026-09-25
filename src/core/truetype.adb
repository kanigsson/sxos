package body Truetype
  with SPARK_Mode => On
is

   --  Composite glyphs may reference composites.  Real fonts nest one level
   --  (Hangul: syllable -> three jamo); this bound just stops a cyclic or
   --  malicious font from recursing forever.
   Max_Depth : constant := 5;

   ---------------------------------------------------------------------------
   --  Bounds-checked big-endian readers.  Every one takes the absolute offset
   --  into F.Data and reports success, so a truncated font can never read out
   --  of range -- the whole file is untrusted input.
   ---------------------------------------------------------------------------

   procedure U8 (F : Font; At_Off : Natural; V : out Unsigned_8; Ok : in out Boolean) is
   begin
      if not Ok or else At_Off > F.Data'Last then
         Ok := False;
         V := 0;
      else
         V := F.Data (At_Off);
      end if;
   end U8;

   procedure U16 (F : Font; At_Off : Natural; V : out Natural; Ok : in out Boolean) is
      A, B : Unsigned_8;
   begin
      U8 (F, At_Off, A, Ok);
      U8 (F, At_Off + 1, B, Ok);
      V := (if Ok then Natural (A) * 256 + Natural (B) else 0);
   end U16;

   --  Signed 16-bit (two's complement), the coordinate/metric encoding.
   procedure S16 (F : Font; At_Off : Natural; V : out Integer; Ok : in out Boolean) is
      U : Natural;
   begin
      U16 (F, At_Off, U, Ok);
      V := (if U >= 32_768 then U - 65_536 else U);
   end S16;

   procedure U32 (F : Font; At_Off : Natural; V : out Unsigned_32; Ok : in out Boolean) is
      Hi, Lo : Natural;
   begin
      U16 (F, At_Off, Hi, Ok);
      U16 (F, At_Off + 2, Lo, Ok);
      V := (if Ok then Shift_Left (Unsigned_32 (Hi), 16) or Unsigned_32 (Lo) else 0);
   end U32;

   ---------------------------------------------------------------------------
   --  Accessors
   ---------------------------------------------------------------------------

   function Units_Per_Em (F : Font) return Positive is (F.Upem);
   function Num_Glyphs   (F : Font) return Natural  is (F.N_Glyphs);
   function Ascent   (F : Font) return Integer is (F.Asc);
   function Descent  (F : Font) return Integer is (F.Desc);
   function Line_Gap (F : Font) return Integer is (F.Gap);

   ----------
   -- Open --
   ----------

   procedure Open (Data : Data_Ref; F : out Font; Ok : out Boolean) is
      Tag        : Unsigned_32;
      N_Tables   : Natural;
      Rec        : Natural;
      Loca_Fmt   : Integer;
      Sub_Count  : Natural;
      Best_Score : Integer := -1;
   begin
      F := (Data => Data, others => <>);
      Ok := Data /= null and then Data'Length >= 12;
      if not Ok then
         return;
      end if;

      --  sfntVersion: 0x00010000 (TrueType outlines) or 'true'.  An OpenType
      --  'OTTO' file holds CFF outlines, which this reader does not decode.
      U32 (F, Data'First, Tag, Ok);
      if not Ok or else (Tag /= 16#0001_0000# and Tag /= 16#7472_7565#) then
         Ok := False;
         return;
      end if;

      U16 (F, Data'First + 4, N_Tables, Ok);
      if not Ok then
         return;
      end if;

      --  Table directory: 16-byte records of tag / checksum / offset / length.
      for I in 0 .. N_Tables - 1 loop
         declare
            Off, Len : Unsigned_32;
            T        : Table;
         begin
            Rec := Data'First + 12 + I * 16;
            U32 (F, Rec, Tag, Ok);
            U32 (F, Rec + 8, Off, Ok);
            U32 (F, Rec + 12, Len, Ok);
            exit when not Ok;

            --  Reject a table that does not lie wholly inside the data before
            --  it is ever indexed.
            if Natural (Off) + Natural (Len) > Data'Length then
               Ok := False;
               exit;
            end if;
            T := (Offset => Data'First + Natural (Off), Length => Natural (Len));

            case Tag is
               when 16#68656164# => F.Head := T;   --  head
               when 16#6D617870# => F.Maxp := T;   --  maxp
               when 16#68686561# => F.Hhea := T;   --  hhea
               when 16#686D7478# => F.Hmtx := T;   --  hmtx
               when 16#6C6F6361# => F.Loca := T;   --  loca
               when 16#676C7966# => F.Glyf := T;   --  glyf
               when 16#636D6170# => F.Cmap := T;   --  cmap
               when others => null;
            end case;
         end;
      end loop;

      if not Ok
        or else F.Head.Length = 0 or else F.Maxp.Length = 0
        or else F.Hhea.Length = 0 or else F.Hmtx.Length = 0
        or else F.Loca.Length = 0 or else F.Glyf.Length = 0
        or else F.Cmap.Length = 0
      then
         Ok := False;
         return;
      end if;

      --  head: unitsPerEm at +18, indexToLocFormat at +50.
      U16 (F, F.Head.Offset + 18, F.Upem, Ok);
      S16 (F, F.Head.Offset + 50, Loca_Fmt, Ok);
      F.Long_Loca := Loca_Fmt = 1;
      if Ok and then F.Upem = 0 then
         Ok := False;
      end if;

      U16 (F, F.Maxp.Offset + 4, F.N_Glyphs, Ok);       --  maxp: numGlyphs at +4
      S16 (F, F.Hhea.Offset + 4, F.Asc, Ok);            --  hhea: ascender
      S16 (F, F.Hhea.Offset + 6, F.Desc, Ok);
      S16 (F, F.Hhea.Offset + 8, F.Gap, Ok);
      U16 (F, F.Hhea.Offset + 34, F.N_HMetrics, Ok);    --  numberOfHMetrics
      if not Ok then
         return;
      end if;

      --  cmap: pick the best Unicode subtable.  Preference order is the usual
      --  one -- (3,10) and (0,4/6) are format 12 full-repertoire tables, (3,1)
      --  and (0,3) the format 4 BMP tables that Korean actually needs.
      U16 (F, F.Cmap.Offset + 2, Sub_Count, Ok);
      for I in 0 .. Sub_Count - 1 loop
         declare
            Plat, Enc, Fmt : Natural;
            Sub_Off        : Unsigned_32;
            Score          : Integer := -1;
            Base           : constant Natural := F.Cmap.Offset + 4 + I * 8;
         begin
            U16 (F, Base, Plat, Ok);
            U16 (F, Base + 2, Enc, Ok);
            U32 (F, Base + 4, Sub_Off, Ok);
            exit when not Ok;

            if (Plat = 3 and then Enc = 10) or else (Plat = 0 and then Enc in 4 | 6) then
               Score := 3;
            elsif (Plat = 3 and then Enc = 1) or else (Plat = 0 and then Enc <= 3) then
               Score := 2;
            end if;

            if Score > Best_Score then
               U16 (F, F.Cmap.Offset + Natural (Sub_Off), Fmt, Ok);
               exit when not Ok;
               if Fmt = 4 or else Fmt = 12 then
                  Best_Score := Score;
                  F.Cmap_Fmt := Fmt;
                  F.Cmap_Sub :=
                    (Offset => F.Cmap.Offset + Natural (Sub_Off), Length => 0);
               end if;
            end if;
         end;
      end loop;

      Ok := Ok and then Best_Score >= 0;
   end Open;

   -----------------
   -- Glyph_Index --
   -----------------

   function Glyph_Index (F : Font; Code : Unsigned_32) return Natural is
      Ok : Boolean := True;
      G  : Natural := 0;
   begin
      if F.Cmap_Fmt = 12 then
         --  Format 12: sorted groups of (startChar, endChar, startGlyph).
         declare
            N_Groups : Unsigned_32;
            Lo       : Natural := 0;
            Hi       : Integer;
            Mid      : Natural;
            S, E, SG : Unsigned_32;
            Base     : constant Natural := F.Cmap_Sub.Offset + 16;
         begin
            U32 (F, F.Cmap_Sub.Offset + 12, N_Groups, Ok);
            if not Ok then
               return 0;
            end if;
            Hi := Natural (N_Groups) - 1;
            while Lo <= Hi loop
               Mid := Lo + (Hi - Lo) / 2;
               U32 (F, Base + Mid * 12, S, Ok);
               U32 (F, Base + Mid * 12 + 4, E, Ok);
               exit when not Ok;
               if Code < S then
                  Hi := Mid - 1;
               elsif Code > E then
                  Lo := Mid + 1;
               else
                  U32 (F, Base + Mid * 12 + 8, SG, Ok);
                  return (if Ok then Natural (SG + (Code - S)) else 0);
               end if;
            end loop;
            return 0;
         end;

      elsif F.Cmap_Fmt = 4 then
         --  Format 4: parallel end/start/delta/rangeOffset arrays over the BMP.
         if Code > 16#FFFF# then
            return 0;
         end if;
         declare
            Seg_X2, Seg_Count : Natural;
            Ends, Starts, Deltas, Ranges : Natural;
            C   : constant Natural := Natural (Code);
            E, S, D, RO : Natural;
            Idx : Natural;
         begin
            U16 (F, F.Cmap_Sub.Offset + 6, Seg_X2, Ok);
            if not Ok or else Seg_X2 = 0 then
               return 0;
            end if;
            Seg_Count := Seg_X2 / 2;
            Ends   := F.Cmap_Sub.Offset + 14;
            Starts := Ends + Seg_X2 + 2;      --  +2 skips reservedPad
            Deltas := Starts + Seg_X2;
            Ranges := Deltas + Seg_X2;

            --  Segments are sorted by endCode; find the first whose end >= C.
            for Seg in 0 .. Seg_Count - 1 loop
               U16 (F, Ends + Seg * 2, E, Ok);
               exit when not Ok;
               if E >= C then
                  U16 (F, Starts + Seg * 2, S, Ok);
                  exit when not Ok;
                  if S > C then
                     return 0;              --  falls in a hole between segments
                  end if;
                  U16 (F, Deltas + Seg * 2, D, Ok);
                  U16 (F, Ranges + Seg * 2, RO, Ok);
                  exit when not Ok;
                  if RO = 0 then
                     G := (C + D) mod 65_536;
                  else
                     --  rangeOffset is a byte offset from its OWN slot into
                     --  glyphIdArray -- the quirk of this format.
                     U16 (F, Ranges + Seg * 2 + RO + (C - S) * 2, Idx, Ok);
                     exit when not Ok;
                     G := (if Idx = 0 then 0 else (Idx + D) mod 65_536);
                  end if;
                  return (if G < F.N_Glyphs then G else 0);
               end if;
            end loop;
            return 0;
         end;
      else
         return 0;
      end if;
   end Glyph_Index;

   -------------
   -- Advance --
   -------------

   function Advance (F : Font; G : Natural) return Natural is
      Ok : Boolean := True;
      A  : Natural;
      --  hmtx holds N_HMetrics (advance, lsb) pairs; every glyph past the last
      --  one shares that final advance (monospaced tail).
      I  : constant Natural :=
        (if F.N_HMetrics = 0 then 0
         elsif G < F.N_HMetrics then G
         else F.N_HMetrics - 1);
   begin
      U16 (F, F.Hmtx.Offset + I * 4, A, Ok);
      return (if Ok then A else 0);
   end Advance;

   ---------------------------------------------------------------------------
   --  Outline decoding
   ---------------------------------------------------------------------------

   --  Byte range of glyph G's entry in glyf, via loca.  An empty range (First =
   --  Last) is a blank glyph such as a space, which is not an error.
   procedure Glyph_Range
     (F : Font; G : Natural; First, Last : out Natural; Ok : in out Boolean)
   is
      A, B : Unsigned_32;
      X, Y : Natural;
   begin
      First := 0;
      Last  := 0;
      if not Ok or else G >= F.N_Glyphs then
         Ok := False;
         return;
      end if;
      if F.Long_Loca then
         U32 (F, F.Loca.Offset + G * 4, A, Ok);
         U32 (F, F.Loca.Offset + G * 4 + 4, B, Ok);
         First := Natural (A);
         Last  := Natural (B);
      else
         --  Short loca stores offsets halved.
         U16 (F, F.Loca.Offset + G * 2, X, Ok);
         U16 (F, F.Loca.Offset + G * 2 + 2, Y, Ok);
         First := X * 2;
         Last  := Y * 2;
      end if;
      if Ok and then (Last < First or else Last > F.Glyf.Length) then
         Ok := False;
      end if;
   end Glyph_Range;

   --  Append glyph G's contours to O, offset by (DX, DY) font units.  Depth
   --  bounds composite recursion.
   procedure Append_Glyph
     (F     : Font;
      G     : Natural;
      DX    : Integer;
      DY    : Integer;
      Depth : Natural;
      O     : in out Outline;
      Ok    : in out Boolean);

   procedure Append_Simple
     (F     : Font;
      Base  : Natural;         --  offset of the glyph entry in the data
      N_Con : Natural;
      DX    : Integer;
      DY    : Integer;
      O     : in out Outline;
      Ok    : in out Boolean)
   is
      P0        : constant Natural := O.N_Points;   --  where this glyph's points start
      N_Pts     : Natural := 0;
      Ins_Len   : Natural;
      Off       : Natural;
      Last_Pt   : Natural;
      Flags     : array (0 .. Max_Points - 1) of Unsigned_8 := (others => 0);
      V, Prev   : Integer;
      B, Rep    : Unsigned_8;
      N         : Natural;
   begin
      if O.N_Contours + N_Con > Max_Contours then
         Ok := False;
         return;
      end if;

      --  endPtsOfContours: the last one gives the point count.
      for I in 0 .. N_Con - 1 loop
         U16 (F, Base + 10 + I * 2, Last_Pt, Ok);
         exit when not Ok;
         O.Ends (O.N_Contours + I) := P0 + Last_Pt;
         if I = N_Con - 1 then
            N_Pts := Last_Pt + 1;
         end if;
      end loop;
      if not Ok then
         return;
      end if;
      if P0 + N_Pts > Max_Points then
         Ok := False;
         return;
      end if;

      --  Skip the hinting bytecode: this reader does not interpret it.
      U16 (F, Base + 10 + N_Con * 2, Ins_Len, Ok);
      Off := Base + 10 + N_Con * 2 + 2 + Ins_Len;
      if not Ok then
         return;
      end if;

      --  Flags, run-length encoded via the REPEAT bit (0x08).
      N := 0;
      while N < N_Pts loop
         U8 (F, Off, B, Ok);
         Off := Off + 1;
         exit when not Ok;
         Flags (N) := B;
         N := N + 1;
         if (B and 16#08#) /= 0 then
            U8 (F, Off, Rep, Ok);
            Off := Off + 1;
            exit when not Ok;
            for K in 1 .. Natural (Rep) loop
               exit when N >= N_Pts;
               Flags (N) := B;
               N := N + 1;
            end loop;
         end if;
      end loop;
      if not Ok then
         return;
      end if;

      --  X then Y, each a delta from the previous point.  Bit 1 (0x02) means a
      --  1-byte magnitude whose sign is bit 4 (0x10); otherwise bit 4 set means
      --  "same as previous" and clear means a signed 2-byte delta.
      Prev := 0;
      for I in 0 .. N_Pts - 1 loop
         if (Flags (I) and 16#02#) /= 0 then
            U8 (F, Off, B, Ok);
            Off := Off + 1;
            V := Natural (B);
            if (Flags (I) and 16#10#) = 0 then
               V := -V;
            end if;
         elsif (Flags (I) and 16#10#) /= 0 then
            V := 0;
         else
            S16 (F, Off, V, Ok);
            Off := Off + 2;
         end if;
         exit when not Ok;
         Prev := Prev + V;
         O.Points (P0 + I) :=
           (X => Prev + DX, Y => 0, On => (Flags (I) and 16#01#) /= 0);
      end loop;
      if not Ok then
         return;
      end if;

      Prev := 0;
      for I in 0 .. N_Pts - 1 loop
         if (Flags (I) and 16#04#) /= 0 then
            U8 (F, Off, B, Ok);
            Off := Off + 1;
            V := Natural (B);
            if (Flags (I) and 16#20#) = 0 then
               V := -V;
            end if;
         elsif (Flags (I) and 16#20#) /= 0 then
            V := 0;
         else
            S16 (F, Off, V, Ok);
            Off := Off + 2;
         end if;
         exit when not Ok;
         Prev := Prev + V;
         O.Points (P0 + I).Y := Prev + DY;
      end loop;
      if not Ok then
         return;
      end if;

      O.N_Points   := P0 + N_Pts;
      O.N_Contours := O.N_Contours + N_Con;
   end Append_Simple;

   procedure Append_Composite
     (F     : Font;
      Base  : Natural;
      DX    : Integer;
      DY    : Integer;
      Depth : Natural;
      O     : in out Outline;
      Ok    : in out Boolean)
   is
      Off        : Natural := Base + 10;
      Raw, Sub   : Natural;
      Flags      : Unsigned_16;
      A1, A2     : Integer;
      More       : Boolean := True;
   begin
      while More and then Ok loop
         U16 (F, Off, Raw, Ok);
         Flags := Unsigned_16 (Raw mod 65_536);
         U16 (F, Off + 2, Sub, Ok);
         Off := Off + 4;
         exit when not Ok;

         --  ARG_1_AND_2_ARE_WORDS (0x0001) picks the argument width.
         if (Flags and 16#0001#) /= 0 then
            S16 (F, Off, A1, Ok);
            S16 (F, Off + 2, A2, Ok);
            Off := Off + 4;
         else
            declare
               B1, B2 : Unsigned_8;
            begin
               U8 (F, Off, B1, Ok);
               U8 (F, Off + 1, B2, Ok);
               Off := Off + 2;
               --  Signed bytes when they are XY values.
               A1 := (if Natural (B1) >= 128 then Natural (B1) - 256 else Natural (B1));
               A2 := (if Natural (B2) >= 128 then Natural (B2) - 256 else Natural (B2));
            end;
         end if;
         exit when not Ok;

         --  Skip any transform.  Hangul composites place jamo by pure
         --  translation (three components, no scale), so a scaled component is
         --  placed at its offset with the scale ignored -- documented here
         --  rather than silently wrong.  WE_HAVE_A_SCALE / X_AND_Y_SCALE /
         --  TWO_BY_TWO are 2 / 4 / 8 bytes of F2Dot14.
         if (Flags and 16#0008#) /= 0 then
            Off := Off + 2;
         elsif (Flags and 16#0040#) /= 0 then
            Off := Off + 4;
         elsif (Flags and 16#0080#) /= 0 then
            Off := Off + 8;
         end if;

         --  ARGS_ARE_XY_VALUES (0x0002); point-matching placement is not used
         --  by any font this targets, so such a component is skipped.
         if (Flags and 16#0002#) /= 0 then
            Append_Glyph (F, Sub, DX + A1, DY + A2, Depth + 1, O, Ok);
         end if;

         More := (Flags and 16#0020#) /= 0;   --  MORE_COMPONENTS
      end loop;
   end Append_Composite;

   procedure Append_Glyph
     (F     : Font;
      G     : Natural;
      DX    : Integer;
      DY    : Integer;
      Depth : Natural;
      O     : in out Outline;
      Ok    : in out Boolean)
   is
      First, Last : Natural;
      N_Con       : Integer;
      Base        : Natural;
   begin
      if Depth > Max_Depth then
         Ok := False;
         return;
      end if;
      Glyph_Range (F, G, First, Last, Ok);
      if not Ok or else First = Last then
         return;                       --  blank glyph: nothing to append
      end if;

      Base := F.Glyf.Offset + First;
      S16 (F, Base, N_Con, Ok);
      if not Ok then
         return;
      end if;

      if N_Con >= 0 then
         Append_Simple (F, Base, N_Con, DX, DY, O, Ok);
      else
         Append_Composite (F, Base, DX, DY, Depth, O, Ok);
      end if;
   end Append_Glyph;

   -----------------
   -- Get_Outline --
   -----------------

   procedure Get_Outline
     (F  : Font;
      G  : Natural;
      O  : out Outline;
      Ok : out Boolean)
   is
   begin
      O := (N_Points => 0, N_Contours => 0,
            Points => (others => (0, 0, False)), Ends => (others => 0));
      Ok := True;
      Append_Glyph (F, G, 0, 0, 0, O, Ok);
   end Get_Outline;

end Truetype;
