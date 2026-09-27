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
   --
   --  An offset handed in is a table offset (at most Max_Data) plus at most a
   --  few 16-bit quantities from the file, which Max_Reach covers with room to
   --  spare.  A successful read also proves its offset lies below Max_Data,
   --  which is what lets a cursor advanced past it stay bounded.
   ---------------------------------------------------------------------------

   Max_Reach : constant := 2**30;

   --  A glyph entry's offset: the glyf table's offset plus an entry offset
   --  that is itself bounded by the table's length.  A cursor walking the
   --  entry may run a few 16-bit quantities past that before a read fails.
   Max_Base : constant := 2 * Max_Data;
   Max_Cursor : constant := Max_Base + 2**18;

   procedure U8 (F : Font; At_Off : Natural; V : out Unsigned_8; Ok : in out Boolean)
     with Post => (if Ok then Ok'Old and then At_Off < Max_Data)
   is
   begin
      if not Ok or else F.Data = null or else At_Off >= Max_Data
        or else At_Off not in F.Data'Range
      then
         Ok := False;
         V := 0;
      else
         V := F.Data (At_Off);
      end if;
   end U8;

   procedure U16 (F : Font; At_Off : Natural; V : out Natural; Ok : in out Boolean)
     with Pre  => At_Off <= Max_Reach,
          Post => V <= 65_535
                  and then (if Ok then Ok'Old and then At_Off + 1 < Max_Data)
   is
      A, B : Unsigned_8;
   begin
      U8 (F, At_Off, A, Ok);
      U8 (F, At_Off + 1, B, Ok);
      V := (if Ok then Natural (A) * 256 + Natural (B) else 0);
   end U16;

   --  Signed 16-bit (two's complement), the coordinate/metric encoding.
   procedure S16 (F : Font; At_Off : Natural; V : out Integer; Ok : in out Boolean)
     with Pre  => At_Off <= Max_Reach,
          Post => V in S16_Value
                  and then (if Ok then Ok'Old and then At_Off + 1 < Max_Data)
   is
      U : Natural;
   begin
      U16 (F, At_Off, U, Ok);
      V := (if U >= 32_768 then U - 65_536 else U);
   end S16;

   procedure U32 (F : Font; At_Off : Natural; V : out Unsigned_32; Ok : in out Boolean)
     with Pre  => At_Off <= Max_Reach - 2,
          Post => (if Ok then Ok'Old and then At_Off + 3 < Max_Data)
   is
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

   -----------------------
   -- Find_Kern_Lookups --
   -----------------------

   --  Collect the pair adjustment lookups (type 2, or 9 for an extension)
   --  that GPOS 'kern' features name, each once: the features of the
   --  default language system of script 'latn', else 'DFLT', else of every
   --  feature (fonts often repeat a pair in each script's lookups, which
   --  must not add up).  Any read failure leaves what was found so far; the
   --  lookups themselves are checked when used.
   procedure Find_Kern_Lookups (F : in out Font) is
      Kern_Tag : constant Unsigned_32 := 16#6B65_726E#;   --  'kern'
      Latn_Tag : constant Unsigned_32 := 16#6C61_746E#;   --  'latn'
      Dflt_Tag : constant Unsigned_32 := 16#4446_4C54#;   --  'DFLT'
      G        : constant Extent := F.Gpos.Offset;
      Ok       : Boolean := True;
      Script_List, Feat_List, Look_List, N_Feat, N_Look : Natural;
      N_Script, Script_Off, Lang_Off, N_Idx, FI : Natural;
      Tag      : Unsigned_32;
      Lang_Sys : Natural := 0;   --  offset of the chosen LangSys, 0: none
      Is_Latn  : Boolean := False;

      --  Add the lookups of feature FI when it is a 'kern' feature.
      procedure Add_Feature (FI : Natural)
        with Pre  => F.N_Kern <= Max_Kern_Lookups and then FI <= 65_535,
             Post => F.N_Kern <= Max_Kern_Lookups
      is
         Feat_Ok : Boolean := True;
         Feat_Off, Count, Idx, Look_Off, Kind : Natural;
         Feat_Tag : Unsigned_32;
         Known    : Boolean;
      begin
         if FI >= N_Feat then
            return;
         end if;
         U32 (F, G + Feat_List + 2 + FI * 6, Feat_Tag, Feat_Ok);
         U16 (F, G + Feat_List + 2 + FI * 6 + 4, Feat_Off, Feat_Ok);
         if not Feat_Ok or else Feat_Tag /= Kern_Tag then
            return;
         end if;
         --  Feature: params offset, index count, lookup indices.
         U16 (F, G + Feat_List + Feat_Off + 2, Count, Feat_Ok);
         if not Feat_Ok then
            return;
         end if;
         for K in 0 .. Count - 1 loop
            pragma Loop_Invariant
              (Feat_Ok and then F.N_Kern <= Max_Kern_Lookups);
            U16 (F, G + Feat_List + Feat_Off + 4 + K * 2, Idx, Feat_Ok);
            exit when not Feat_Ok;
            Known := False;
            for J in 1 .. F.N_Kern loop
               if F.Kern_Looks (J).Index = Idx then
                  Known := True;
               end if;
            end loop;
            if not Known and then Idx < N_Look
              and then F.N_Kern < Max_Kern_Lookups
            then
               U16 (F, G + Look_List + 2 + Idx * 2, Look_Off, Feat_Ok);
               exit when not Feat_Ok;
               U16 (F, G + Look_List + Look_Off, Kind, Feat_Ok);
               exit when not Feat_Ok;
               if Kind = 2 or else Kind = 9 then
                  F.N_Kern := F.N_Kern + 1;
                  F.Kern_Looks (F.N_Kern) :=
                    (Index => Idx, Offset => G + Look_List + Look_Off);
               end if;
            end if;
         end loop;
      end Add_Feature;

   begin
      F.N_Kern := 0;
      if F.Gpos.Length < 10 then
         return;
      end if;
      U16 (F, G + 4, Script_List, Ok);
      U16 (F, G + 6, Feat_List, Ok);
      U16 (F, G + 8, Look_List, Ok);
      if not Ok then
         return;
      end if;
      U16 (F, G + Feat_List, N_Feat, Ok);
      U16 (F, G + Look_List, N_Look, Ok);
      if not Ok then
         return;
      end if;

      --  The script: 'latn', else 'DFLT'.
      U16 (F, G + Script_List, N_Script, Ok);
      if Ok then
         for I in 0 .. N_Script - 1 loop
            pragma Loop_Invariant (Ok);
            U32 (F, G + Script_List + 2 + I * 6, Tag, Ok);
            U16 (F, G + Script_List + 2 + I * 6 + 4, Script_Off, Ok);
            exit when not Ok;
            if Tag = Latn_Tag or else (Tag = Dflt_Tag and then not Is_Latn)
            then
               --  Script: its default LangSys offset comes first.
               U16 (F, G + Script_List + Script_Off, Lang_Off, Ok);
               exit when not Ok;
               if Lang_Off /= 0 then
                  Lang_Sys := G + Script_List + Script_Off + Lang_Off;
                  Is_Latn := Tag = Latn_Tag;
               end if;
            end if;
         end loop;
      end if;

      if Lang_Sys /= 0 then
         --  LangSys: lookup order, required feature, feature indices.
         Ok := True;
         U16 (F, Lang_Sys + 4, N_Idx, Ok);
         if Ok then
            for K in 0 .. N_Idx - 1 loop
               pragma Loop_Invariant (Ok and then F.N_Kern <= Max_Kern_Lookups);
               U16 (F, Lang_Sys + 6 + K * 2, FI, Ok);
               exit when not Ok;
               Add_Feature (FI);
            end loop;
         end if;
      else
         for I in 0 .. N_Feat - 1 loop
            pragma Loop_Invariant (F.N_Kern <= Max_Kern_Lookups);
            Add_Feature (I);
         end loop;
      end if;
   end Find_Kern_Lookups;

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
      V          : Natural;
      S          : Integer;
   begin
      F := (Data => Data, others => <>);
      --  A file of Max_Data bytes or more is refused outright; see the
      --  declaration of Max_Data.
      Ok := Data /= null and then Data'Length >= 12
        and then Data'Last < Max_Data;
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
         pragma Loop_Invariant (Ok);
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
            --  it is ever indexed.  Compared in the file's own 32-bit type, so
            --  that neither field can overflow on the way.
            if Off > Unsigned_32 (Data'Length)
              or else Len > Unsigned_32 (Data'Length) - Off
            then
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
               when 16#47504F53# => F.Gpos := T;   --  GPOS
               when 16#6B65726E# => F.Kern := T;   --  kern
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

      --  The readers take F itself, so each value is read into a local
      --  before it is stored in F.

      --  head: unitsPerEm at +18, indexToLocFormat at +50.
      U16 (F, F.Head.Offset + 18, V, Ok);
      if Ok and then V = 0 then
         Ok := False;
      elsif Ok then
         F.Upem := V;
      end if;
      S16 (F, F.Head.Offset + 50, Loca_Fmt, Ok);
      F.Long_Loca := Loca_Fmt = 1;

      U16 (F, F.Maxp.Offset + 4, V, Ok);                --  maxp: numGlyphs at +4
      F.N_Glyphs := V;
      S16 (F, F.Hhea.Offset + 4, S, Ok);                --  hhea: ascender
      F.Asc := S;
      S16 (F, F.Hhea.Offset + 6, S, Ok);
      F.Desc := S;
      S16 (F, F.Hhea.Offset + 8, S, Ok);
      F.Gap := S;
      U16 (F, F.Hhea.Offset + 34, V, Ok);               --  numberOfHMetrics
      F.N_HMetrics := V;
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
               --  An offset this far out cannot be read; failing here is what
               --  the read below would do.
               if Sub_Off >= Max_Data then
                  Ok := False;
                  exit;
               end if;
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
      if Ok then
         Find_Kern_Lookups (F);
      end if;
   end Open;

   -----------------
   -- Glyph_Index --
   -----------------

   function Glyph_Index (F : Font; Code : Unsigned_32) return Natural is
      Ok : Boolean := True;
   begin
      if F.Cmap_Fmt = 12 then
         --  Format 12: sorted groups of (startChar, endChar, startGlyph).
         declare
            --  A group is 12 bytes, so no readable table holds more groups
            --  than this; a larger count is corrupt.
            Max_Groups : constant := Max_Data / 12;
            N_Groups : Unsigned_32;
            Lo       : Natural := 0;
            Hi       : Integer;
            Mid      : Natural;
            S, E, SG : Unsigned_32;
            Base     : constant Natural := F.Cmap_Sub.Offset + 16;
         begin
            U32 (F, F.Cmap_Sub.Offset + 12, N_Groups, Ok);
            if not Ok or else N_Groups > Max_Groups then
               return 0;
            end if;
            Hi := Natural (N_Groups) - 1;
            while Lo <= Hi loop
               pragma Loop_Invariant (Lo <= Max_Groups and then Hi < Max_Groups);
               pragma Loop_Variant (Decreases => Hi - Lo);
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
                  --  An id past the font's glyphs is as absent as a code
                  --  point no group covers (format 4 below does the same).
                  if not Ok
                    or else SG >= Unsigned_32 (F.N_Glyphs)
                    or else Code - S >= Unsigned_32 (F.N_Glyphs) - SG
                  then
                     return 0;
                  end if;
                  return Natural (SG + (Code - S));
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
            G   : Natural;
            Lo, Hi, Mid : Natural;
            Seg : Natural;
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

            --  Segments are sorted by endCode; find the first whose end >= C
            --  by bisection (a CJK face has thousands of segments).  In a
            --  table that is not sorted this finds some segment, or none,
            --  and the glyph id is checked as always.
            Lo := 0;
            Hi := Seg_Count;
            while Lo < Hi loop
               pragma Loop_Invariant (Hi <= Seg_Count);
               pragma Loop_Variant (Decreases => Hi - Lo);
               Mid := Lo + (Hi - Lo) / 2;
               U16 (F, Ends + Mid * 2, E, Ok);
               if not Ok then
                  return 0;
               end if;
               if E < C then
                  Lo := Mid + 1;
               else
                  Hi := Mid;
               end if;
            end loop;
            if Lo >= Seg_Count then
               return 0;
            end if;
            Seg := Lo;

            U16 (F, Starts + Seg * 2, S, Ok);
            if not Ok or else S > C then
               return 0;              --  falls in a hole between segments
            end if;
            U16 (F, Deltas + Seg * 2, D, Ok);
            if not Ok then
               return 0;
            end if;
            U16 (F, Ranges + Seg * 2, RO, Ok);
            if not Ok then
               return 0;
            end if;
            if RO = 0 then
               G := (C + D) mod 65_536;
            else
               --  rangeOffset is a byte offset from its OWN slot into
               --  glyphIdArray -- the quirk of this format.
               U16 (F, Ranges + Seg * 2 + RO + (C - S) * 2, Idx, Ok);
               if not Ok then
                  return 0;
               end if;
               G := (if Idx = 0 then 0 else (Idx + D) mod 65_536);
            end if;
            return (if G < F.N_Glyphs then G else 0);
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
     with Post => (if Ok then Ok'Old and then First <= Last
                              and then Last <= F.Glyf.Length)
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
         --  Checked in the file's 32-bit type, before either end is taken
         --  as a Natural.
         if Ok and then (B < A or else B > Unsigned_32 (F.Glyf.Length)) then
            Ok := False;
         elsif Ok then
            First := Natural (A);
            Last  := Natural (B);
         end if;
      else
         --  Short loca stores offsets halved.
         U16 (F, F.Loca.Offset + G * 2, X, Ok);
         U16 (F, F.Loca.Offset + G * 2 + 2, Y, Ok);
         First := X * 2;
         Last  := Y * 2;
         if Ok and then (Last < First or else Last > F.Glyf.Length) then
            Ok := False;
         end if;
      end if;
   end Glyph_Range;

   --  One 16-bit span: the reach of a glyph coordinate or of a component
   --  offset.  Offsets accumulate one span per composite level, which is
   --  what bounds a decoded point (see Coord).
   Span : constant := 32_768;

   --  Append glyph G's contours to O, offset by (DX, DY) font units.  Depth
   --  bounds composite recursion.
   procedure Append_Glyph
     (F     : Font;
      G     : Natural;
      DX    : Integer;
      DY    : Integer;
      Depth : Natural;
      O     : in out Outline;
      Ok    : in out Boolean)
     with Pre  => Depth <= Max_Depth + 1
                  and then DX in -(Depth * Span) .. Depth * Span
                  and then DY in -(Depth * Span) .. Depth * Span
                  and then Well_Formed (O),
          Post => Well_Formed (O);

   procedure Append_Simple
     (F     : Font;
      Base  : Natural;         --  offset of the glyph entry in the data
      N_Con : Natural;
      DX    : Integer;
      DY    : Integer;
      O     : in out Outline;
      Ok    : in out Boolean)
     with Pre  => Base <= Max_Base
                  and then N_Con < Span
                  and then DX in -(Max_Depth * Span) .. Max_Depth * Span
                  and then DY in -(Max_Depth * Span) .. Max_Depth * Span
                  and then Well_Formed (O),
          Post => Well_Formed (O)
   is
      P0        : constant Natural := O.N_Points;   --  where this glyph's points start
      C0        : constant Natural := O.N_Contours; --  and its contours
      N_Pts     : Natural;
      Prev_End  : Integer := -1;   --  the last contour end read, glyph-relative
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

      --  endPtsOfContours: the last one gives the point count.  The ends
      --  must increase and stay within the point bound; a font where they do
      --  not is corrupt, and would otherwise hand the rasteriser a contour
      --  spanning points this glyph never decoded.
      for I in 0 .. N_Con - 1 loop
         pragma Loop_Invariant
           (Well_Formed (O)
            and then Prev_End in -1 .. Max_Points - 1 - P0
            and then (if I > 0 then Prev_End >= 0
                      and then O.Ends (O.N_Contours + I - 1) = P0 + Prev_End)
            and then (for all J in 0 .. I - 1 =>
                        O.Ends (O.N_Contours + J) >= P0
                        and then O.Ends (O.N_Contours + J) <= P0 + Prev_End
                        and then (if J > 0 then O.Ends (O.N_Contours + J - 1)
                                                < O.Ends (O.N_Contours + J))));
         U16 (F, Base + 10 + I * 2, Last_Pt, Ok);
         exit when not Ok;
         if Last_Pt <= Prev_End or else Last_Pt >= Max_Points - P0 then
            Ok := False;
            exit;
         end if;
         O.Ends (O.N_Contours + I) := P0 + Last_Pt;
         Prev_End := Last_Pt;
      end loop;
      if not Ok then
         return;
      end if;
      N_Pts := Prev_End + 1;

      --  What the new contours bring: ends from P0 up to the last point.
      pragma Assert
        (for all J in 0 .. N_Con - 1 =>
           O.Ends (O.N_Contours + J) in P0 .. P0 + N_Pts - 1
           and then (if J > 0 then O.Ends (O.N_Contours + J - 1)
                                   < O.Ends (O.N_Contours + J)));

      --  Skip the hinting bytecode: this reader does not interpret it.
      U16 (F, Base + 10 + N_Con * 2, Ins_Len, Ok);
      Off := Base + 10 + N_Con * 2 + 2 + Ins_Len;
      if not Ok then
         return;
      end if;

      --  Flags, run-length encoded via the REPEAT bit (0x08).
      N := 0;
      while N < N_Pts loop
         pragma Loop_Invariant (Ok and then Off <= Max_Cursor);
         pragma Loop_Variant (Increases => N);
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
               pragma Loop_Invariant (N < N_Pts and then N >= N'Loop_Entry);
               Flags (N) := B;
               N := N + 1;
            end loop;
         end if;
      end loop;
      if not Ok then
         return;
      end if;

      --  Restated after each pass over the points, which leaves the ends
      --  alone; the prover needs it carried across.
      pragma Assert
        (for all I in C0 .. C0 + N_Con - 1 =>
           O.Ends (I) in P0 .. P0 + N_Pts - 1
           and then (if I > C0 then O.Ends (I - 1) < O.Ends (I)));

      --  X then Y, each a delta from the previous point.  Bit 1 (0x02) means a
      --  1-byte magnitude whose sign is bit 4 (0x10); otherwise bit 4 set means
      --  "same as previous" and clear means a signed 2-byte delta.  An
      --  absolute coordinate is a 16-bit FWORD, so deltas that leave that
      --  range mark a corrupt glyph.
      Prev := 0;
      for I in 0 .. N_Pts - 1 loop
         pragma Loop_Invariant
           (Ok and then Off <= Max_Cursor and then Prev in S16_Value
            and then Well_Formed (O));
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
         if Prev not in S16_Value then
            Ok := False;
            exit;
         end if;
         O.Points (P0 + I) :=
           (X => Prev + DX, Y => 0, On => (Flags (I) and 16#01#) /= 0);
      end loop;
      if not Ok then
         return;
      end if;

      --  Restated after each pass over the points, which leaves the ends
      --  alone; the prover needs it carried across.
      pragma Assert
        (for all I in C0 .. C0 + N_Con - 1 =>
           O.Ends (I) in P0 .. P0 + N_Pts - 1
           and then (if I > C0 then O.Ends (I - 1) < O.Ends (I)));
      Prev := 0;
      for I in 0 .. N_Pts - 1 loop
         pragma Loop_Invariant
           (Ok and then Off <= Max_Cursor and then Prev in S16_Value
            and then Well_Formed (O));
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
         if Prev not in S16_Value then
            Ok := False;
            exit;
         end if;
         O.Points (P0 + I).Y := Prev + DY;
      end loop;
      if not Ok then
         return;
      end if;

      --  Restated once more, then split old contours from new, for the
      --  postcondition.
      pragma Assert
        (for all I in C0 .. C0 + N_Con - 1 =>
           O.Ends (I) in P0 .. P0 + N_Pts - 1
           and then (if I > C0 then O.Ends (I - 1) < O.Ends (I)));
      pragma Assert (if C0 > 0 then O.Ends (C0 - 1) < P0);
      O.N_Points   := P0 + N_Pts;
      O.N_Contours := O.N_Contours + N_Con;
      pragma Assert
        (for all I in 0 .. C0 - 1 =>
           O.Ends (I) < O.N_Points
           and then (if I > 0 then O.Ends (I - 1) < O.Ends (I)));
      pragma Assert
        (for all I in C0 .. O.N_Contours - 1 =>
           O.Ends (I) < O.N_Points
           and then (if I > 0 then O.Ends (I - 1) < O.Ends (I)));
   end Append_Simple;

   procedure Append_Composite
     (F     : Font;
      Base  : Natural;
      DX    : Integer;
      DY    : Integer;
      Depth : Natural;
      O     : in out Outline;
      Ok    : in out Boolean)
     with Pre  => Base <= Max_Base
                  and then Depth <= Max_Depth
                  and then DX in -(Depth * Span) .. Depth * Span
                  and then DY in -(Depth * Span) .. Depth * Span
                  and then Well_Formed (O),
          Post => Well_Formed (O)
   is
      Off        : Natural := Base + 10;
      Raw, Sub   : Natural;
      Flags      : Unsigned_16;
      A1, A2     : Integer;
      More       : Boolean := True;
   begin
      while More and then Ok loop
         pragma Loop_Invariant (Off <= Max_Cursor and then Well_Formed (O));
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

   ---------------------------------------------------------------------------
   --  Kerning
   ---------------------------------------------------------------------------

   --  Every GPOS offset below is a table offset (at most Max_Data) plus a
   --  few 16-bit quantities, or the result of a successful read (then below
   --  Max_Data) plus a few more: all well inside Max_Reach.

   function Clamp16 (V : Long_Long_Integer) return Integer is
     (Integer (Long_Long_Integer'Max (-32_768, Long_Long_Integer'Min (32_767, V))))
   with Post => Clamp16'Result in -32_768 .. 32_767;

   --  The size of a value record of format Fmt, and the offset of its X
   --  advance within it (Has_X False when it has none).
   function Value_Size (Fmt : Natural) return Natural is
     (2 * ((Fmt mod 2) + (Fmt / 2 mod 2) + (Fmt / 4 mod 2) + (Fmt / 8 mod 2)
           + (Fmt / 16 mod 2) + (Fmt / 32 mod 2) + (Fmt / 64 mod 2)
           + (Fmt / 128 mod 2)))
   with Post => Value_Size'Result <= 16;

   function X_Advance_At (Fmt : Natural) return Natural is
     (2 * ((Fmt mod 2) + (Fmt / 2 mod 2)))
   with Post => X_Advance_At'Result <= 4;

   function Has_X_Advance (Fmt : Natural) return Boolean is
     (Fmt / 4 mod 2 = 1);

   --  Glyph G's index in the coverage table at Cov.
   procedure Coverage_Index
     (F : Font; Cov : Natural; G : Natural;
      Idx : out Natural; Found : out Boolean)
     with Pre  => Cov <= Max_Data + 2**17,
          Post => Idx <= 2 * 65_535
   is
      Ok    : Boolean := True;
      Fmt, N, Mid, V, S, E, Base_I : Natural;
      Lo    : Natural := 0;
      Hi    : Integer;
   begin
      Idx := 0;
      Found := False;
      U16 (F, Cov, Fmt, Ok);
      U16 (F, Cov + 2, N, Ok);
      if not Ok or else N = 0 then
         return;
      end if;
      Hi := N - 1;
      if Fmt = 1 then
         --  A sorted glyph array; the index is the position.
         while Lo <= Hi loop
            pragma Loop_Invariant (Lo <= 65_535 and then Hi < 65_535);
            pragma Loop_Variant (Decreases => Hi - Lo);
            Mid := Lo + (Hi - Lo) / 2;
            U16 (F, Cov + 4 + Mid * 2, V, Ok);
            exit when not Ok;
            if G < V then
               Hi := Mid - 1;
            elsif G > V then
               Lo := Mid + 1;
            else
               Idx := Mid;
               Found := True;
               return;
            end if;
         end loop;
      elsif Fmt = 2 then
         --  Sorted ranges of (start, end, start coverage index).
         while Lo <= Hi loop
            pragma Loop_Invariant (Lo <= 65_535 and then Hi < 65_535);
            pragma Loop_Variant (Decreases => Hi - Lo);
            Mid := Lo + (Hi - Lo) / 2;
            U16 (F, Cov + 4 + Mid * 6, S, Ok);
            U16 (F, Cov + 4 + Mid * 6 + 2, E, Ok);
            exit when not Ok;
            if G < S then
               Hi := Mid - 1;
            elsif G > E then
               Lo := Mid + 1;
            else
               U16 (F, Cov + 4 + Mid * 6 + 4, Base_I, Ok);
               exit when not Ok;
               Idx := Base_I + (G - S);
               Found := Idx <= 2 * 65_535;
               if not Found then
                  Idx := 0;
               end if;
               return;
            end if;
         end loop;
      end if;
   end Coverage_Index;

   --  Glyph G's class in the class definition table at CD (0 by default).
   function Class_Of (F : Font; CD : Natural; G : Natural) return Natural
     with Pre  => CD <= Max_Data + 2**17,
          Post => Class_Of'Result <= 65_535
   is
      Ok  : Boolean := True;
      Fmt, First, N, Mid, S, E, V : Natural;
      Lo  : Natural := 0;
      Hi  : Integer;
   begin
      U16 (F, CD, Fmt, Ok);
      if not Ok then
         return 0;
      end if;
      if Fmt = 1 then
         --  Classes of a run of glyphs from First.
         U16 (F, CD + 2, First, Ok);
         U16 (F, CD + 4, N, Ok);
         if Ok and then G >= First and then G - First < N then
            U16 (F, CD + 6 + (G - First) * 2, V, Ok);
            return (if Ok then V else 0);
         end if;
      elsif Fmt = 2 then
         U16 (F, CD + 2, N, Ok);
         if not Ok or else N = 0 then
            return 0;
         end if;
         Hi := N - 1;
         while Lo <= Hi loop
            pragma Loop_Invariant (Lo <= 65_535 and then Hi < 65_535);
            pragma Loop_Variant (Decreases => Hi - Lo);
            Mid := Lo + (Hi - Lo) / 2;
            U16 (F, CD + 4 + Mid * 6, S, Ok);
            U16 (F, CD + 4 + Mid * 6 + 2, E, Ok);
            exit when not Ok;
            if G < S then
               Hi := Mid - 1;
            elsif G > E then
               Lo := Mid + 1;
            else
               U16 (F, CD + 4 + Mid * 6 + 4, V, Ok);
               return (if Ok then V else 0);
            end if;
         end loop;
      end if;
      return 0;
   end Class_Of;

   --  The pair adjustment subtable I of kern lookup L: its offset (Sub)
   --  and format (1 or 2; 0 for anything this reader does not apply).
   procedure Pair_Subtable
     (F : Font; L : Positive; I : Natural; Sub : out Natural;
      Fmt : out Natural)
     with Pre  => L <= F.N_Kern and then I <= 65_535,
          Post => Sub < Max_Data and then Fmt <= 2
   is
      Look     : constant Extent := F.Kern_Looks (L).Offset;
      Ok       : Boolean := True;
      Kind, Off, Ext_Kind, Raw : Natural;
      Ext_Off  : Unsigned_32;
      Base     : Natural;
   begin
      Sub := 0;
      Fmt := 0;
      U16 (F, Look, Kind, Ok);
      U16 (F, Look + 6 + I * 2, Off, Ok);
      if not Ok then
         return;
      end if;
      Base := Look + Off;
      if Kind = 9 then
         --  Extension: format 1, the real lookup type, a 32-bit offset.
         U16 (F, Base + 2, Ext_Kind, Ok);
         U32 (F, Base + 4, Ext_Off, Ok);
         if not Ok or else Ext_Kind /= 2 or else Ext_Off >= Max_Data then
            return;
         end if;
         Base := Base + Natural (Ext_Off);
      elsif Kind /= 2 then
         return;
      end if;
      U16 (F, Base, Raw, Ok);
      if Ok and then (Raw = 1 or else Raw = 2) then
         Sub := Base;
         Fmt := Raw;
      end if;
   end Pair_Subtable;

   --  The number of subtables of kern lookup L.
   function Subtable_Count (F : Font; L : Positive) return Natural
     with Pre  => L <= F.N_Kern,
          Post => Subtable_Count'Result <= 65_535
   is
      Ok : Boolean := True;
      N  : Natural;
   begin
      U16 (F, F.Kern_Looks (L).Offset + 4, N, Ok);
      return (if Ok then N else 0);
   end Subtable_Count;

   --  The adjustment for Left then Right in the pair subtable at Sub of
   --  format Fmt, and whether the subtable applies to the pair (then no
   --  later subtable of its lookup does).
   procedure Pair_Value
     (F : Font; Sub : Natural; Fmt : Natural; Left, Right : Natural;
      V : out Integer; Matched : out Boolean)
     with Pre  => Sub < Max_Data,
          Post => V in -32_768 .. 32_767
   is
      Ok   : Boolean := True;
      Cov, VF1, VF2, CI, Count, PS_Off, Size, Mid, Second : Natural;
      Found : Boolean;
      Lo    : Natural := 0;
      Hi    : Integer;
   begin
      V := 0;
      Matched := False;
      U16 (F, Sub + 2, Cov, Ok);
      U16 (F, Sub + 4, VF1, Ok);
      U16 (F, Sub + 6, VF2, Ok);
      if not Ok then
         return;
      end if;
      Coverage_Index (F, Sub + Cov, Left, CI, Found);
      if not Found then
         return;
      end if;
      if Fmt = 1 then
         --  Pair sets, one per covered first glyph, of records (second
         --  glyph, value 1, value 2) sorted by the second glyph.
         U16 (F, Sub + 8, Count, Ok);
         if not Ok or else CI >= Count then
            return;
         end if;
         U16 (F, Sub + 10 + CI * 2, PS_Off, Ok);
         U16 (F, Sub + PS_Off, Count, Ok);
         if not Ok or else Count = 0 then
            return;
         end if;
         Size := 2 + Value_Size (VF1) + Value_Size (VF2);
         Hi := Count - 1;
         while Lo <= Hi loop
            pragma Loop_Invariant (Lo <= 65_535 and then Hi < 65_535);
            pragma Loop_Variant (Decreases => Hi - Lo);
            Mid := Lo + (Hi - Lo) / 2;
            U16 (F, Sub + PS_Off + 2 + Mid * Size, Second, Ok);
            exit when not Ok;
            if Right < Second then
               Hi := Mid - 1;
            elsif Right > Second then
               Lo := Mid + 1;
            else
               Matched := True;
               if Has_X_Advance (VF1) then
                  S16 (F, Sub + PS_Off + 2 + Mid * Size + 2
                          + X_Advance_At (VF1), V, Ok);
                  if not Ok then
                     V := 0;
                  end if;
               end if;
               return;
            end if;
         end loop;
      else
         declare
            CD1, CD2, N1, N2, C1, C2 : Natural;
            Rec : Long_Long_Integer;
         begin
            U16 (F, Sub + 8, CD1, Ok);
            U16 (F, Sub + 10, CD2, Ok);
            U16 (F, Sub + 12, N1, Ok);
            U16 (F, Sub + 14, N2, Ok);
            if not Ok then
               return;
            end if;
            C1 := Class_Of (F, Sub + CD1, Left);
            C2 := Class_Of (F, Sub + CD2, Right);
            if C1 >= N1 or else C2 >= N2 then
               return;
            end if;
            Matched := True;
            if Has_X_Advance (VF1) then
               Rec := (Long_Long_Integer (C1) * Long_Long_Integer (N2)
                       + Long_Long_Integer (C2))
                 * Long_Long_Integer (Value_Size (VF1) + Value_Size (VF2));
               if Rec < Max_Data then
                  S16 (F, Sub + 16 + Natural (Rec) + X_Advance_At (VF1),
                       V, Ok);
                  if not Ok then
                     V := 0;
                  end if;
               end if;
            end if;
         end;
      end if;
   end Pair_Value;

   --  The legacy kern table's horizontal format 0 subtables, in turn: Next
   --  moves P (the first byte of a subtable, 0 for the first) on to the
   --  next usable one and gives its pair count; P is 0 when there is none.
   procedure Next_Legacy
     (F : Font; P : in out Natural; N_Pairs : out Natural)
     with Pre  => P < Max_Data,
          Post => P < Max_Data and then N_Pairs <= 65_535
   is
      Ok       : Boolean := True;
      Version, N_Tables, Len, Cov : Natural;
      Q        : Natural;
   begin
      N_Pairs := 0;
      if F.Kern.Length < 4 then
         P := 0;
         return;
      end if;
      U16 (F, F.Kern.Offset, Version, Ok);
      U16 (F, F.Kern.Offset + 2, N_Tables, Ok);
      if not Ok or else Version /= 0 or else N_Tables = 0 then
         P := 0;
         return;
      end if;
      if P = 0 then
         Q := F.Kern.Offset + 4;
      else
         U16 (F, P + 2, Len, Ok);
         if not Ok or else Len < 6 then
            P := 0;
            return;
         end if;
         Q := P + Len;
      end if;
      --  Subtables must lie inside the table; at most N_Tables of them.
      for K in 1 .. N_Tables loop
         pragma Loop_Invariant (Ok and then Q <= Max_Data + 2**17);
         exit when Q + 14 > F.Kern.Offset + F.Kern.Length;
         U16 (F, Q + 2, Len, Ok);
         U16 (F, Q + 4, Cov, Ok);
         U16 (F, Q + 6, N_Pairs, Ok);
         exit when not Ok or else Len < 6;
         --  Format 0 (high byte), horizontal, not minimum, not
         --  cross-stream.
         if Cov / 256 = 0 and then Cov mod 8 = 1 then
            P := Q;
            return;
         end if;
         exit when Q + Len >= Max_Data;
         Q := Q + Len;
      end loop;
      P := 0;
      N_Pairs := 0;
   end Next_Legacy;

   -------------
   -- Kerning --
   -------------

   function Kerning (F : Font; Left, Right : Natural) return Integer is
      Sum : Long_Long_Integer := 0;
      Sub, Fmt : Natural;
      V   : Integer;
      Matched : Boolean;
   begin
      if Left = 0 or else Right = 0 then
         return 0;
      end if;
      if F.N_Kern > 0 then
         for L in 1 .. F.N_Kern loop
            pragma Loop_Invariant (abs Sum <= Long_Long_Integer (L - 1) * 32_768);
            for I in 0 .. Subtable_Count (F, L) - 1 loop
               Pair_Subtable (F, L, I, Sub, Fmt);
               if Fmt /= 0 then
                  Pair_Value (F, Sub, Fmt, Left, Right, V, Matched);
                  if Matched then
                     Sum := Sum + Long_Long_Integer (V);
                     exit;
                  end if;
               end if;
            end loop;
         end loop;
         return Clamp16 (Sum);
      end if;

      --  Legacy: pairs sorted by (left, right), summed over subtables.
      declare
         P        : Natural := 0;
         N        : Natural;
         Ok       : Boolean;
         Lo, Mid  : Natural;
         Hi       : Integer;
         A, B     : Natural;
      begin
         for Guard in 1 .. 16 loop
            pragma Loop_Invariant (abs Sum <= Long_Long_Integer (Guard - 1) * 32_768);
            Next_Legacy (F, P, N);
            exit when P = 0;
            Lo := 0;
            Hi := N - 1;
            Ok := True;
            while Lo <= Hi loop
               pragma Loop_Invariant (Lo <= 65_535 and then Hi < 65_535);
               pragma Loop_Variant (Decreases => Hi - Lo);
               Mid := Lo + (Hi - Lo) / 2;
               U16 (F, P + 14 + Mid * 6, A, Ok);
               U16 (F, P + 14 + Mid * 6 + 2, B, Ok);
               exit when not Ok;
               if Left < A or else (Left = A and then Right < B) then
                  Hi := Mid - 1;
               elsif Left > A or else Right > B then
                  Lo := Mid + 1;
               else
                  S16 (F, P + 14 + Mid * 6 + 4, V, Ok);
                  if Ok then
                     Sum := Sum + Long_Long_Integer (V);
                  end if;
                  exit;
               end if;
            end loop;
         end loop;
      end;
      return Clamp16 (Sum);
   end Kerning;

   --------------------
   -- Kerning_Matrix --
   --------------------

   procedure Kerning_Matrix
     (F       : Font;
      Glyphs  : Glyph_List;
      M       : in out Kern_Matrix;
      Settled : in out Flag_Matrix)
   is
      N : constant Natural := Glyphs'Length;

      --  Positions in Glyphs, ordered by glyph id, to find every entry of
      --  a glyph that a table names.
      Order : array (0 .. Max_Kern_Glyphs - 1) of Natural := (others => 0);

      --  Add V to the pair (I, J) unless an earlier subtable of the
      --  current lookup settled it (Once) -- the legacy table has no such
      --  rule.
      procedure Add (I, J : Natural; V : Integer; Once : Boolean)
        with Pre => I < N and then J < N and then V in -32_768 .. 32_767
      is
         K : constant Natural := I * N + J;
      begin
         if Once and then Settled (K) then
            return;
         end if;
         M (K) := Integer_16 (Clamp16 (Long_Long_Integer (M (K))
                                       + Long_Long_Integer (V)));
         Settled (K) := True;
      end Add;

      --  The first position in Order whose glyph is at least G (N if none).
      function First_At_Least (G : Natural) return Natural
        with Post => First_At_Least'Result <= N
      is
         Lo : Natural := 0;
         Hi : Natural := N;
         Mid : Natural;
      begin
         while Lo < Hi loop
            pragma Loop_Invariant (Lo < Hi and then Hi <= N);
            pragma Loop_Variant (Decreases => Hi - Lo);
            Mid := Lo + (Hi - Lo) / 2;
            if Order (Mid) < N and then Glyphs (Order (Mid)) < G then
               Lo := Mid + 1;
            else
               Hi := Mid;
            end if;
         end loop;
         return Lo;
      end First_At_Least;

      Sub, Fmt : Natural;
   begin
      for K in M'Range loop
         M (K) := 0;
      end loop;
      if N = 0 then
         return;
      end if;

      --  Insertion sort of the positions by glyph: N is a few hundred.
      for I in 0 .. N - 1 loop
         declare
            P : Natural := I;
         begin
            while P > 0 and then Order (P - 1) < N
              and then Glyphs (Order (P - 1)) > Glyphs (I)
            loop
               pragma Loop_Invariant (P <= I);
               pragma Loop_Variant (Decreases => P);
               Order (P) := Order (P - 1);
               P := P - 1;
            end loop;
            Order (P) := I;
         end;
      end loop;

      if F.N_Kern > 0 then
         for L in 1 .. F.N_Kern loop
            for K in Settled'Range loop
               Settled (K) := False;
            end loop;
            for S in 0 .. Subtable_Count (F, L) - 1 loop
               Pair_Subtable (F, L, S, Sub, Fmt);
               if Fmt = 1 then
                  declare
                     Ok : Boolean := True;
                     Cov, VF1, VF2, CI, Count, PS_Off, Size, Second : Natural;
                     Found : Boolean;
                     V  : Integer;
                     P  : Natural;
                  begin
                     U16 (F, Sub + 2, Cov, Ok);
                     U16 (F, Sub + 4, VF1, Ok);
                     U16 (F, Sub + 6, VF2, Ok);
                     U16 (F, Sub + 8, Count, Ok);
                     Size := 2 + Value_Size (VF1) + Value_Size (VF2);
                     for I in 0 .. N - 1 loop
                        exit when not Ok;
                        if Glyphs (I) /= 0 then
                           Coverage_Index (F, Sub + Cov, Glyphs (I), CI, Found);
                           if Found and then CI < Count then
                              U16 (F, Sub + 10 + CI * 2, PS_Off, Ok);
                              declare
                                 Pairs : Natural := 0;
                                 Ok2   : Boolean := Ok;
                              begin
                                 U16 (F, Sub + PS_Off, Pairs, Ok2);
                                 for R in 0 .. (if Ok2 then Pairs else 0) - 1 loop
                                    U16 (F, Sub + PS_Off + 2 + R * Size,
                                         Second, Ok2);
                                    exit when not Ok2;
                                    V := 0;
                                    if Has_X_Advance (VF1) then
                                       S16 (F, Sub + PS_Off + 2 + R * Size + 2
                                               + X_Advance_At (VF1), V, Ok2);
                                       exit when not Ok2;
                                    end if;
                                    P := First_At_Least (Second);
                                    while P < N and then Order (P) < N
                                      and then Glyphs (Order (P)) = Second
                                    loop
                                       pragma Loop_Variant (Increases => P);
                                       if Second /= 0 then
                                          Add (I, Order (P), V, Once => True);
                                       end if;
                                       P := P + 1;
                                    end loop;
                                 end loop;
                              end;
                           end if;
                        end if;
                     end loop;
                  end;
               elsif Fmt = 2 then
                  declare
                     Ok : Boolean := True;
                     Cov, VF1, VF2, CD1, CD2, N1, N2, CI, C1 : Natural;
                     Found : Boolean;
                     Size  : Natural;
                     Rec   : Long_Long_Integer;
                     V     : Integer;
                     C2    : array (0 .. Max_Kern_Glyphs - 1) of Natural :=
                       (others => 0);
                  begin
                     U16 (F, Sub + 2, Cov, Ok);
                     U16 (F, Sub + 4, VF1, Ok);
                     U16 (F, Sub + 6, VF2, Ok);
                     U16 (F, Sub + 8, CD1, Ok);
                     U16 (F, Sub + 10, CD2, Ok);
                     U16 (F, Sub + 12, N1, Ok);
                     U16 (F, Sub + 14, N2, Ok);
                     Size := Value_Size (VF1) + Value_Size (VF2);
                     if Ok then
                        for J in 0 .. N - 1 loop
                           C2 (J) := Class_Of (F, Sub + CD2, Glyphs (J));
                        end loop;
                        for I in 0 .. N - 1 loop
                           if Glyphs (I) /= 0 then
                              Coverage_Index
                                (F, Sub + Cov, Glyphs (I), CI, Found);
                              C1 := (if Found
                                     then Class_Of (F, Sub + CD1, Glyphs (I))
                                     else N1);
                              if C1 < N1 then
                                 for J in 0 .. N - 1 loop
                                    if Glyphs (J) /= 0 and then C2 (J) < N2
                                      and then not Settled (I * N + J)
                                    then
                                       V := 0;
                                       Rec := (Long_Long_Integer (C1)
                                               * Long_Long_Integer (N2)
                                               + Long_Long_Integer (C2 (J)))
                                         * Long_Long_Integer (Size);
                                       if Has_X_Advance (VF1)
                                         and then Rec < Max_Data
                                       then
                                          S16 (F, Sub + 16 + Natural (Rec)
                                                  + X_Advance_At (VF1), V, Ok);
                                          if not Ok then
                                             V := 0;
                                             Ok := True;
                                          end if;
                                       end if;
                                       Add (I, J, V, Once => True);
                                    end if;
                                 end loop;
                              end if;
                           end if;
                        end loop;
                     end if;
                  end;
               end if;
            end loop;
         end loop;
         return;
      end if;

      --  Legacy: walk every pair of each subtable.
      declare
         P  : Natural := 0;
         NP : Natural;
         Ok : Boolean;
         A, B : Natural;
         V  : Integer;
         PA, PB : Natural;
      begin
         for Guard in 1 .. 16 loop
            Next_Legacy (F, P, NP);
            exit when P = 0;
            Ok := True;
            for R in 0 .. NP - 1 loop
               U16 (F, P + 14 + R * 6, A, Ok);
               U16 (F, P + 14 + R * 6 + 2, B, Ok);
               S16 (F, P + 14 + R * 6 + 4, V, Ok);
               exit when not Ok;
               if A /= 0 and then B /= 0 then
                  PA := First_At_Least (A);
                  while PA < N and then Order (PA) < N
                    and then Glyphs (Order (PA)) = A
                  loop
                     pragma Loop_Variant (Increases => PA);
                     PB := First_At_Least (B);
                     while PB < N and then Order (PB) < N
                       and then Glyphs (Order (PB)) = B
                     loop
                        pragma Loop_Variant (Increases => PB);
                        Add (Order (PA), Order (PB), V, Once => False);
                        PB := PB + 1;
                     end loop;
                     PA := PA + 1;
                  end loop;
               end if;
            end loop;
         end loop;
      end;
   end Kerning_Matrix;

end Truetype;
