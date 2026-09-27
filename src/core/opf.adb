package body Opf
  with SPARK_Mode => On
is
   function Rootfile (Container : String) return Span is
      Pos   : Positive :=
        (if Container'Length > 0 then Container'First else 1);
      Tag   : Span;
      Value : Span;
      Found : Boolean;
   begin
      if Container'Length = 0 then
         return (First => 1, Last => 0);
      end if;
      loop
         pragma Loop_Variant (Increases => Pos);
         Next_Tag (Container, Pos, Tag, Found);
         exit when not Found;
         if Is_Start (Container, Tag, "rootfile") then
            Attribute (Container, Tag, "full-path", Value, Found);
            if Found then
               return Value;
            end if;
         end if;
      end loop;
      return (First => 1, Last => 0);
   end Rootfile;

   function Language (Doc : String) return Span is
      Pos    : Positive := (if Doc'Length > 0 then Doc'First else 1);
      Tag    : Span;
      Found  : Boolean;
      Result : Span := (First => 1, Last => 0);
   begin
      if Doc'Length = 0 then
         return Result;
      end if;
      loop
         pragma Loop_Invariant (Pos >= Doc'First);
         pragma Loop_Variant (Increases => Pos);
         Next_Tag (Doc, Pos, Tag, Found);
         exit when not Found;
         if Is_Start (Doc, Tag, "language") and then Pos <= Doc'Last then
            --  The content, up to the next tag, without white space.
            Result := (First => Pos, Last => Pos - 1);
            while Result.Last < Doc'Last and then Doc (Result.Last + 1) /= '<'
            loop
               pragma Loop_Invariant
                 (Result.First = Pos
                  and then Result.Last in Pos - 1 .. Doc'Last);
               pragma Loop_Variant (Increases => Result.Last);
               Result.Last := Result.Last + 1;
            end loop;
            --  Leading blanks: a last blank left alone here goes with the
            --  trailing ones below, and stopping short of Result.Last keeps
            --  the step in range.
            while Result.First < Result.Last
              and then Doc (Result.First) <= ' '
            loop
               pragma Loop_Invariant
                 (Result.First in Pos .. Result.Last
                  and then Result.Last <= Doc'Last);
               pragma Loop_Variant (Increases => Result.First);
               Result.First := Result.First + 1;
            end loop;
            while Result.Last >= Result.First
              and then Doc (Result.Last) <= ' '
            loop
               pragma Loop_Invariant
                 (Result.First >= Pos
                  and then Result.Last in Result.First .. Doc'Last);
               pragma Loop_Variant (Decreases => Result.Last);
               Result.Last := Result.Last - 1;
            end loop;
            return Result;
         end if;
      end loop;
      return Result;
   end Language;

   function Count_Tags (Doc : String; Name : String) return Natural is
      Pos   : Positive := (if Doc'Length > 0 then Doc'First else 1);
      Tag   : Span;
      Found : Boolean;
      N     : Natural := 0;
   begin
      if Doc'Length = 0 then
         return 0;
      end if;
      loop
         pragma Loop_Variant (Increases => Pos);
         Next_Tag (Doc, Pos, Tag, Found);
         exit when not Found;
         if Is_Start (Doc, Tag, Name) and then N < Natural'Last then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Count_Tags;

   function Count_Items (Doc : String) return Natural is
     (Count_Tags (Doc, "item"));
   function Count_Itemrefs (Doc : String) return Natural is
     (Count_Tags (Doc, "itemref"));

   --  Does the media type name an (X)HTML document?
   function Is_Html_Type (T : String) return Boolean is
     (Same_Text (T, "application/xhtml+xml") or else Same_Text (T, "text/html"));

   --  Is Token one of the blank-separated words of S?
   function Has_Word (S : String; Token : String) return Boolean is
      I : Natural := S'First;
      E : Natural;
   begin
      if S'Length = 0 or else Token'Length = 0 then
         return False;
      end if;
      loop
         pragma Loop_Invariant (I in S'Range);
         pragma Loop_Variant (Increases => I);
         if S (I) = ' ' then
            exit when I = S'Last;
            I := I + 1;
         else
            E := I;
            while E < S'Last and then S (E + 1) /= ' ' loop
               pragma Loop_Invariant (E in I .. S'Last - 1);
               pragma Loop_Variant (Increases => E);
               E := E + 1;
            end loop;
            if S (I .. E) = Token then
               return True;
            end if;
            exit when E = S'Last;
            I := E + 1;
         end if;
      end loop;
      return False;
   end Has_Word;

   procedure Read_Manifest
     (Doc   : String;
      Items : out Item_Array;
      Count : out Natural)
   is
      Pos   : Positive := (if Doc'Length > 0 then Doc'First else 1);
      Tag   : Span;
      Found : Boolean;
      Id, Href, Kind, Props : Span;
      Has_Id, Has_Href, Has_Kind, Has_Props : Boolean;
   begin
      Items := (others => (Id => (1, 0), Href => (1, 0), others => False));
      Count := 0;
      if Doc'Length = 0 then
         return;
      end if;
      loop
         pragma Loop_Invariant (Count <= Items'Length);
         Next_Tag (Doc, Pos, Tag, Found);
         exit when not Found or else Count >= Items'Length;
         if Is_Start (Doc, Tag, "item") then
            Attribute (Doc, Tag, "id", Id, Has_Id);
            Attribute (Doc, Tag, "href", Href, Has_Href);
            Attribute (Doc, Tag, "media-type", Kind, Has_Kind);
            Attribute (Doc, Tag, "properties", Props, Has_Props);
            if Has_Id and then Has_Href then
               Count := Count + 1;
               Items (Items'First + (Count - 1)) :=
                 (Id   => Id,
                  Href => Href,
                  Html => Has_Kind and then Is_Html_Type (Text (Doc, Kind)),
                  Nav  => Has_Props and then Has_Word (Text (Doc, Props), "nav"),
                  Ncx  => Has_Kind and then Same_Text
                            (Text (Doc, Kind), "application/x-dtbncx+xml"));
            end if;
         end if;
      end loop;
   end Read_Manifest;

   procedure Read_Spine
     (Doc   : String;
      Items : Item_Array;
      Spine : out Span_Array;
      Count : out Natural)
   is
      Pos    : Positive := (if Doc'Length > 0 then Doc'First else 1);
      Tag    : Span;
      Found  : Boolean;
      Ref    : Span;
      Next   : Natural := 0;   --  where to start looking in Items
      In_Spine : Boolean := False;
   begin
      Spine := (others => (1, 0));
      Count := 0;
      if Doc'Length = 0 or else Items'Length = 0 then
         return;
      end if;
      loop
         pragma Loop_Invariant
           (Count <= Spine'Length and then Next < Items'Length);
         Next_Tag (Doc, Pos, Tag, Found);
         exit when not Found or else Count >= Spine'Length;
         if Is_Start (Doc, Tag, "spine") then
            In_Spine := True;
         elsif Is_End (Doc, Tag, "spine") then
            exit;
         elsif In_Spine and then Is_Start (Doc, Tag, "itemref") then
            Attribute (Doc, Tag, "idref", Ref, Found);
            if Found then
               --  The spine usually follows manifest order: search on from
               --  the previous match, wrapping around once.
               for K in 0 .. Items'Length - 1 loop
                  pragma Loop_Invariant
                    (Count < Spine'Length and then Next < Items'Length);
                  declare
                     --  (Next + K) mod Items'Length, without the sum.
                     I : constant Positive :=
                       Items'First
                       + (if K < Items'Length - Next then Next + K
                          else K - (Items'Length - Next));
                  begin
                     if Within (Doc, Items (I).Id)
                       and then Text (Doc, Items (I).Id) = Text (Doc, Ref)
                     then
                        if Items (I).Html and then Within (Doc, Items (I).Href)
                        then
                           Count := Count + 1;
                           Spine (Spine'First + (Count - 1)) := Items (I).Href;
                        end if;
                        Next := (I - Items'First + 1) mod Items'Length;
                        exit;
                     end if;
                  end;
               end loop;
            end if;
         end if;
      end loop;
   end Read_Spine;

   procedure Toc_Hrefs
     (Items : Item_Array;
      Nav   : out Span;
      Ncx   : out Span)
   is
   begin
      Nav := (1, 0);
      Ncx := (1, 0);
      for It of Items loop
         if It.Nav and then Is_Empty (Nav) then
            Nav := It.Href;
         end if;
         if It.Ncx and then Is_Empty (Ncx) then
            Ncx := It.Href;
         end if;
      end loop;
   end Toc_Hrefs;

   function Hex (C : Character) return Integer is
     (case C is
         when '0' .. '9' => Character'Pos (C) - Character'Pos ('0'),
         when 'a' .. 'f' => Character'Pos (C) - Character'Pos ('a') + 10,
         when 'A' .. 'F' => Character'Pos (C) - Character'Pos ('A') + 10,
         when others     => -1);

   procedure Resolve
     (Base : String;
      Href : String;
      Path : out String;
      Last : out Natural;
      Ok   : out Boolean)
   is
      L : Natural := 0;
      P : Natural := (if Href'Length > 0 then Href'First else 0);

      procedure Put (C : Character) is
      begin
         if L < Path'Last then
            L := L + 1;
            Path (L) := C;
         else
            Ok := False;
         end if;
      end Put;

      R, W, Seg_End : Natural;
   begin
      Path := (others => ' ');
      Last := 0;
      Ok := True;

      --  Base's folder, unless Href is absolute.
      if Href'Length > 0 and then Href (Href'First) = '/' then
         P := (if Href'Length > 1 then Href'First + 1 else 0);
      else
         for K in reverse Base'Range loop
            if Base (K) = '/' then
               for J in Base'First .. K loop
                  pragma Loop_Invariant (L = 0 or else L <= Path'Last);
                  Put (Base (J));
               end loop;
               exit;
            end if;
         end loop;
      end if;

      --  Href up to a fragment or query, decoded.  A step that would leave
      --  Href ends the loop instead, so P never goes past Href'Last + 1.
      while P in Href'Range loop
         pragma Loop_Invariant (L = 0 or else L <= Path'Last);
         exit when Href (P) = '#' or else Href (P) = '?';
         if Href (P) = '%' and then P <= Href'Last - 2
           and then Hex (Href (P + 1)) >= 0 and then Hex (Href (P + 2)) >= 0
         then
            Put (Character'Val (Hex (Href (P + 1)) * 16 + Hex (Href (P + 2))));
            exit when Href'Last - P < 3;
            P := P + 3;
         elsif Href (P) = '&' and then P <= Href'Last - 4
           and then Href (P .. P + 4) = "&amp;"
         then
            Put ('&');
            exit when Href'Last - P < 5;
            P := P + 5;
         else
            Put (Href (P));
            exit when P = Href'Last;
            P := P + 1;
         end if;
         exit when not Ok;
      end loop;
      if not Ok then
         return;
      end if;

      --  Resolve "." and ".." in place (the write index never passes the
      --  read index).
      R := 1;
      W := 0;
      while R <= L loop
         pragma Loop_Invariant
           (L <= Path'Last and then R >= 1
            and then (W = 0 or else W <= R - 2));
         Seg_End := R;
         while Seg_End <= L and then Path (Seg_End) /= '/' loop
            pragma Loop_Invariant (Seg_End in R .. L);
            Seg_End := Seg_End + 1;
         end loop;
         --  The segment is Path (R .. Seg_End - 1).
         if Seg_End = R or else (Seg_End - R = 1 and then Path (R) = '.') then
            null;
         elsif Seg_End - R = 2 and then Path (R .. R + 1) = ".." then
            while W > 0 and then Path (W) /= '/' loop
               pragma Loop_Invariant (W <= R - 2);
               W := W - 1;
            end loop;
            if W > 0 then
               W := W - 1;   --  drop the separator too
            end if;
         else
            if W > 0 then
               W := W + 1;
               Path (W) := '/';
            end if;
            for K in R .. Seg_End - 1 loop
               pragma Loop_Invariant
                 (W - W'Loop_Entry = K - R and then W < K);
               W := W + 1;
               Path (W) := Path (K);
            end loop;
         end if;
         --  Seg_End is at most L + 1: stop rather than step past it.
         exit when Seg_End >= L;
         R := Seg_End + 1;
      end loop;
      Last := W;
   end Resolve;
end Opf;
