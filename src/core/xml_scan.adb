package body Xml_Scan
  with SPARK_Mode => On
is
   function Is_Space (C : Character) return Boolean is
     (C = ' ' or else C = ASCII.HT or else C = ASCII.LF or else C = ASCII.CR);

   function Lower (C : Character) return Character is
     (if C in 'A' .. 'Z'
      then Character'Val (Character'Pos (C) + 32) else C);

   function Same_Text (A, B : String) return Boolean is
   begin
      if A'Length /= B'Length then
         return False;
      end if;
      for K in 0 .. A'Length - 1 loop
         if Lower (A (A'First + K)) /= Lower (B (B'First + K)) then
            return False;
         end if;
      end loop;
      return True;
   end Same_Text;

   procedure Next_Tag
     (Doc   : String;
      Pos   : in out Positive;
      Tag   : out Span;
      Found : out Boolean)
   is
      P : Natural := Pos;
   begin
      Tag := (First => 1, Last => 0);
      Found := False;
      while P <= Doc'Last and then P >= Doc'First loop
         pragma Loop_Invariant (P >= Pos and then not Found);
         pragma Loop_Variant (Increases => P);
         if Doc (P) = '<' then
            if P <= Doc'Last - 3 and then Doc (P + 1 .. P + 3) = "!--" then
               --  Skip the comment to its "-->", searching from just after
               --  the "<!--".  Q + 1 is where the search is: stepping from
               --  the comment opener's last byte keeps every index in Doc.
               declare
                  Q : Natural := P + 3;
               begin
                  while Q < Doc'Last - 2 and then Doc (Q + 1 .. Q + 3) /= "-->"
                  loop
                     pragma Loop_Invariant (Q in P + 3 .. Doc'Last - 3);
                     pragma Loop_Variant (Increases => Q);
                     Q := Q + 1;
                  end loop;
                  --  Unterminated, or the "-->" ends Doc: nothing follows.
                  exit when Q >= Doc'Last - 3;
                  P := Q + 4;
               end;
            else
               exit when P = Doc'Last;   --  unterminated tag
               for Q in P + 1 .. Doc'Last loop
                  if Doc (Q) = '>' then
                     Tag := (First => P + 1, Last => Q - 1);
                     Found := True;
                     Pos := (if Q < Positive'Last then Q + 1 else Q);
                     return;
                  end if;
               end loop;
               exit;   --  unterminated tag
            end if;
         else
            exit when P = Natural'Last;
            P := P + 1;
         end if;
      end loop;
      if Doc'Last in 0 .. Positive'Last - 1 then
         Pos := Doc'Last + 1;
      elsif Doc'Last = Positive'Last then
         Pos := Doc'Last;
      end if;
   end Next_Tag;

   --  Tag's name (from First, which follows '<' or '</'), without a prefix.
   function Local_Name_Is
     (Doc : String; First, Last : Positive; Name : String) return Boolean
     with Pre => First >= Doc'First and then Last <= Doc'Last
                 and then Last < Positive'Last
   is
      E : Natural := First;
      S : Positive := First;
   begin
      while E <= Last and then not Is_Space (Doc (E))
        and then Doc (E) /= '/' and then Doc (E) /= '>'
      loop
         pragma Loop_Invariant (E in First .. Last and then S in First .. E);
         pragma Loop_Variant (Increases => E);
         if Doc (E) = ':' and then E < Last then
            S := E + 1;
         end if;
         E := E + 1;
      end loop;
      return E > S and then Same_Text (Doc (S .. E - 1), Name);
   end Local_Name_Is;

   procedure Tag_Name
     (Doc     : String;
      Tag     : Span;
      Name    : out Span;
      Closing : out Boolean)
   is
      S, E : Natural;
   begin
      Name := (First => 1, Last => 0);
      Closing := False;
      if Is_Empty (Tag) or else Doc (Tag.First) = '!' or else Doc (Tag.First) = '?'
      then
         return;
      end if;
      S := Tag.First;
      if Doc (S) = '/' then
         Closing := True;
         if S = Tag.Last then
            return;
         end if;
         S := S + 1;
      end if;
      E := S;
      while E <= Tag.Last and then not Is_Space (Doc (E)) and then Doc (E) /= '/'
      loop
         pragma Loop_Invariant
           (E in Tag.First .. Tag.Last and then S in Tag.First .. E);
         pragma Loop_Variant (Increases => E);
         if Doc (E) = ':' and then E < Tag.Last then
            S := E + 1;
         end if;
         E := E + 1;
      end loop;
      if E > S then
         Name := (First => S, Last => E - 1);
      end if;
   end Tag_Name;

   function Is_Start (Doc : String; Tag : Span; Name : String) return Boolean is
     (not Is_Empty (Tag)
      and then Doc (Tag.First) /= '/'
      and then Doc (Tag.First) /= '!'
      and then Doc (Tag.First) /= '?'
      and then Local_Name_Is (Doc, Tag.First, Tag.Last, Name));

   function Is_End (Doc : String; Tag : Span; Name : String) return Boolean is
     (Tag.Last > Tag.First
      and then Doc (Tag.First) = '/'
      and then Local_Name_Is (Doc, Tag.First + 1, Tag.Last, Name));

   procedure Attribute
     (Doc   : String;
      Tag   : Span;
      Name  : String;
      Value : out Span;
      Found : out Boolean)
   is
      P          : Natural := Tag.First;
      Name_First : Positive;
      Name_Last  : Natural;
      Quote      : Character;
   begin
      Value := (First => 1, Last => 0);
      Found := False;
      if Is_Empty (Tag) then
         return;
      end if;
      --  Skip the element name.
      while P <= Tag.Last and then not Is_Space (Doc (P)) loop
         pragma Loop_Invariant (P in Tag.First .. Tag.Last);
         pragma Loop_Variant (Increases => P);
         P := P + 1;
      end loop;
      loop
         pragma Loop_Invariant (P in Tag.First .. Tag.Last + 1);
         pragma Loop_Invariant (not Found);
         pragma Loop_Variant (Increases => P);
         while P <= Tag.Last and then Is_Space (Doc (P)) loop
            pragma Loop_Invariant (P in P'Loop_Entry .. Tag.Last);
            pragma Loop_Variant (Increases => P);
            P := P + 1;
         end loop;
         exit when P > Tag.Last;
         Name_First := P;
         while P <= Tag.Last and then Doc (P) /= '='
           and then not Is_Space (Doc (P))
         loop
            pragma Loop_Invariant (P in Name_First .. Tag.Last);
            pragma Loop_Variant (Increases => P);
            P := P + 1;
         end loop;
         Name_Last := P - 1;
         while P <= Tag.Last and then Is_Space (Doc (P)) loop
            pragma Loop_Invariant (P in Name_First .. Tag.Last);
            pragma Loop_Variant (Increases => P);
            P := P + 1;
         end loop;
         exit when P > Tag.Last or else Doc (P) /= '=';
         P := P + 1;
         while P <= Tag.Last and then Is_Space (Doc (P)) loop
            pragma Loop_Invariant (P in Name_First .. Tag.Last);
            pragma Loop_Variant (Increases => P);
            P := P + 1;
         end loop;
         exit when P > Tag.Last
           or else (Doc (P) /= '"' and then Doc (P) /= ''');
         Quote := Doc (P);
         P := P + 1;
         declare
            V_First : constant Positive := P;
         begin
            while P <= Tag.Last and then Doc (P) /= Quote loop
               pragma Loop_Invariant (P in V_First .. Tag.Last);
               pragma Loop_Variant (Increases => P);
               P := P + 1;
            end loop;
            if Name_Last >= Name_First then
               --  Drop a namespace prefix from the attribute name.
               for K in reverse Name_First .. Name_Last loop
                  if Doc (K) = ':' then
                     Name_First := K + 1;
                     exit;
                  end if;
               end loop;
               if Name_Last >= Name_First
                 and then Same_Text (Doc (Name_First .. Name_Last), Name)
               then
                  Value := (First => V_First, Last => P - 1);
                  Found := True;
                  return;
               end if;
            end if;
         end;
         exit when P >= Tag.Last;
         P := P + 1;
      end loop;
   end Attribute;
end Xml_Scan;
