package body Toc
  with SPARK_Mode => On
is
   function Count_Links (Doc : String; Is_Nav : Boolean) return Natural is
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
         if Is_Start (Doc, Tag, (if Is_Nav then "a" else "content"))
           and then N < Natural'Last
         then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Count_Links;

   --  Is Token one of the blank-separated words of Doc (V)?
   function Has_Word (Doc : String; V : Span; Token : String) return Boolean
     with Pre => Within (Doc, V)
   is
      I : Positive := V.First;
      E : Positive;
   begin
      if Is_Empty (V) or else Token'Length = 0 then
         return False;
      end if;
      loop
         pragma Loop_Invariant (I in V.First .. V.Last);
         pragma Loop_Variant (Increases => I);
         if Doc (I) = ' ' then
            exit when I = V.Last;
            I := I + 1;
         else
            E := I;
            while E < V.Last and then Doc (E + 1) /= ' ' loop
               pragma Loop_Invariant (E in I .. V.Last - 1);
               pragma Loop_Variant (Increases => E);
               E := E + 1;
            end loop;
            if Doc (I .. E) = Token then
               return True;
            end if;
            exit when E = V.Last;
            I := E + 1;
         end if;
      end loop;
      return False;
   end Has_Word;

   --  Where the toc nav's content starts (just past its start tag): the
   --  nav whose epub:type has "toc", else the first nav; 0 if none.
   function Nav_Start (Doc : String) return Natural
     with Pre => Doc'Length > 0
   is
      Pos   : Positive := Doc'First;
      Tag   : Span;
      Found : Boolean;
      Kind  : Span;
      Typed : Boolean;
      First : Natural := 0;
   begin
      loop
         pragma Loop_Variant (Increases => Pos);
         Next_Tag (Doc, Pos, Tag, Found);
         exit when not Found;
         if Is_Start (Doc, Tag, "nav") then
            Attribute (Doc, Tag, "type", Kind, Typed);
            if Typed and then Has_Word (Doc, Kind, "toc") then
               return Pos;
            elsif First = 0 then
               First := Pos;
            end if;
         end if;
      end loop;
      return First;
   end Nav_Start;

   procedure Read_Nav
     (Doc   : String;
      Items : out Item_Array;
      Count : out Natural)
     with Pre  => Doc'Length > 0,
          Post => Count <= Items'Length
                  and then (for all K in Items'First .. Items'First + Count - 1
                            => Within (Doc, Items (K).Label)
                               and then Within (Doc, Items (K).Href))
   is
      Start : constant Natural := Nav_Start (Doc);
      Pos   : Positive := (if Start = 0 then Doc'First else Start);
      Tag   : Span;
      Found : Boolean;
      Href  : Span;
      Depth : Natural := 0;   --  open <ol>s
      Label : Span;
   begin
      Items := (others => (Level => 1, Label => (1, 0), Href => (1, 0)));
      Count := 0;
      if Start = 0 or else Start > Doc'Last then
         return;
      end if;
      loop
         pragma Loop_Invariant
           (Count <= Items'Length and then Pos >= Doc'First
            and then (for all K in Items'First .. Items'First + Count - 1
                      => Within (Doc, Items (K).Label)
                         and then Within (Doc, Items (K).Href)));
         pragma Loop_Variant (Increases => Pos);
         Next_Tag (Doc, Pos, Tag, Found);
         exit when not Found or else Count >= Items'Length;
         if Is_End (Doc, Tag, "nav") then
            exit;
         elsif Is_Start (Doc, Tag, "ol") then
            if Depth < Natural'Last then
               Depth := Depth + 1;
            end if;
         elsif Is_End (Doc, Tag, "ol") then
            if Depth > 0 then
               Depth := Depth - 1;
            end if;
         elsif Is_Start (Doc, Tag, "a") then
            Attribute (Doc, Tag, "href", Href, Found);
            if Found and then not Is_Empty (Href) and then Pos <= Doc'Last then
               --  The label runs up to the </a>.
               Label := (First => Pos, Last => Pos - 1);
               loop
                  pragma Loop_Invariant
                    (Label.First = Pos'Loop_Entry
                     and then Label.Last = Pos'Loop_Entry - 1
                     and then Pos >= Pos'Loop_Entry);
                  pragma Loop_Variant (Increases => Pos);
                  Next_Tag (Doc, Pos, Tag, Found);
                  exit when not Found;
                  if Is_End (Doc, Tag, "a") then
                     --  The '<' of the end tag is at Tag.First - 1.
                     Label.Last := Tag.First - 2;
                     exit;
                  end if;
               end loop;
               Count := Count + 1;
               Items (Items'First + (Count - 1)) :=
                 (Level => Natural'Max (1, Natural'Min (Depth, Max_Level)),
                  Label => Label,
                  Href  => Href);
               exit when not Found;
            end if;
         end if;
      end loop;
   end Read_Nav;

   procedure Read_Ncx
     (Doc   : String;
      Items : out Item_Array;
      Count : out Natural)
     with Pre  => Doc'Length > 0,
          Post => Count <= Items'Length
                  and then (for all K in Items'First .. Items'First + Count - 1
                            => Within (Doc, Items (K).Label)
                               and then Within (Doc, Items (K).Href))
   is
      Pos    : Positive := Doc'First;
      Tag    : Span;
      Found  : Boolean;
      In_Map : Boolean := False;
      Depth  : Natural := 0;   --  open <navPoint>s
      Label  : Span := (1, 0);
      Href   : Span;
   begin
      Items := (others => (Level => 1, Label => (1, 0), Href => (1, 0)));
      Count := 0;
      loop
         pragma Loop_Invariant
           (Count <= Items'Length and then Pos >= Doc'First
            and then Within (Doc, Label)
            and then (for all K in Items'First .. Items'First + Count - 1
                      => Within (Doc, Items (K).Label)
                         and then Within (Doc, Items (K).Href)));
         pragma Loop_Variant (Increases => Pos);
         Next_Tag (Doc, Pos, Tag, Found);
         exit when not Found or else Count >= Items'Length;
         if Is_Start (Doc, Tag, "navMap") then
            In_Map := True;
         elsif Is_End (Doc, Tag, "navMap") then
            exit;
         elsif not In_Map then
            null;
         elsif Is_Start (Doc, Tag, "navPoint") then
            if Depth < Natural'Last then
               Depth := Depth + 1;
            end if;
            Label := (1, 0);
         elsif Is_End (Doc, Tag, "navPoint") then
            if Depth > 0 then
               Depth := Depth - 1;
            end if;
         elsif Is_Start (Doc, Tag, "text") and then Pos <= Doc'Last then
            --  The label is the text up to the next tag.
            Label := (First => Pos, Last => Pos - 1);
            while Label.Last < Doc'Last and then Doc (Label.Last + 1) /= '<'
            loop
               pragma Loop_Invariant
                 (Label.First = Pos and then Label.Last in Pos - 1 .. Doc'Last);
               pragma Loop_Variant (Increases => Label.Last);
               Label.Last := Label.Last + 1;
            end loop;
         elsif Is_Start (Doc, Tag, "content") then
            Attribute (Doc, Tag, "src", Href, Found);
            if Found and then not Is_Empty (Href) then
               Count := Count + 1;
               Items (Items'First + (Count - 1)) :=
                 (Level => Natural'Max (1, Natural'Min (Depth, Max_Level)),
                  Label => Label,
                  Href  => Href);
            end if;
         end if;
      end loop;
   end Read_Ncx;

   procedure Read
     (Doc    : String;
      Is_Nav : Boolean;
      Items  : out Item_Array;
      Count  : out Natural)
   is
   begin
      if Doc'Length = 0 then
         Items := (others => (Level => 1, Label => (1, 0), Href => (1, 0)));
         Count := 0;
      elsif Is_Nav then
         Read_Nav (Doc, Items, Count);
      else
         Read_Ncx (Doc, Items, Count);
      end if;
   end Read;
end Toc;
