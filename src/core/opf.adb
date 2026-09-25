package body Opf
  with SPARK_Mode => On
is
   function Rootfile (Container : String) return Span is
      Pos   : Positive := Container'First;
      Tag   : Span;
      Value : Span;
      Found : Boolean;
   begin
      if Container'Length = 0 then
         return (First => 1, Last => 0);
      end if;
      loop
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

   procedure Read_Manifest
     (Doc   : String;
      Items : out Item_Array;
      Count : out Natural)
   is
      Pos   : Positive := (if Doc'Length > 0 then Doc'First else 1);
      Tag   : Span;
      Found : Boolean;
      Id, Href, Kind : Span;
      Has_Id, Has_Href, Has_Kind : Boolean;
   begin
      Items := (others => (Id => (1, 0), Href => (1, 0), Html => False));
      Count := 0;
      if Doc'Length = 0 then
         return;
      end if;
      loop
         Next_Tag (Doc, Pos, Tag, Found);
         exit when not Found or else Count >= Items'Length;
         if Is_Start (Doc, Tag, "item") then
            Attribute (Doc, Tag, "id", Id, Has_Id);
            Attribute (Doc, Tag, "href", Href, Has_Href);
            Attribute (Doc, Tag, "media-type", Kind, Has_Kind);
            if Has_Id and then Has_Href then
               Count := Count + 1;
               Items (Items'First + Count - 1) :=
                 (Id   => Id,
                  Href => Href,
                  Html => Has_Kind and then Is_Html_Type (Text (Doc, Kind)));
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
                  declare
                     I : constant Positive :=
                       Items'First + (Next + K) mod Items'Length;
                  begin
                     if Within (Doc, Items (I).Id)
                       and then Text (Doc, Items (I).Id) = Text (Doc, Ref)
                     then
                        if Items (I).Html and then Within (Doc, Items (I).Href)
                        then
                           Count := Count + 1;
                           Spine (Spine'First + Count - 1) := Items (I).Href;
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
      P : Natural := Href'First;

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
         P := Href'First + 1;
      else
         for K in reverse Base'Range loop
            if Base (K) = '/' then
               for J in Base'First .. K loop
                  Put (Base (J));
               end loop;
               exit;
            end if;
         end loop;
      end if;

      --  Href up to a fragment or query, decoded.
      while P in Href'Range loop
         exit when Href (P) = '#' or else Href (P) = '?';
         if Href (P) = '%' and then P <= Href'Last - 2
           and then Hex (Href (P + 1)) >= 0 and then Hex (Href (P + 2)) >= 0
         then
            Put (Character'Val (Hex (Href (P + 1)) * 16 + Hex (Href (P + 2))));
            P := P + 3;
         elsif Href (P) = '&' and then P <= Href'Last - 4
           and then Href (P .. P + 4) = "&amp;"
         then
            Put ('&');
            P := P + 5;
         else
            Put (Href (P));
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
         Seg_End := R;
         while Seg_End <= L and then Path (Seg_End) /= '/' loop
            Seg_End := Seg_End + 1;
         end loop;
         --  The segment is Path (R .. Seg_End - 1).
         if Seg_End = R or else (Seg_End = R + 1 and then Path (R) = '.') then
            null;
         elsif Seg_End = R + 2 and then Path (R .. R + 1) = ".." then
            while W > 0 and then Path (W) /= '/' loop
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
               W := W + 1;
               Path (W) := Path (K);
            end loop;
         end if;
         R := Seg_End + 1;
      end loop;
      Last := W;
   end Resolve;
end Opf;
