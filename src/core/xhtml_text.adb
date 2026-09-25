with UTF8;
with Xml_Scan; use Xml_Scan;

package body Xhtml_Text
  with SPARK_Mode => On
is
   use type UTF8.Code_Point;

   --  Named entities: the XML five, Latin-1 and common typography.
   type Entity is record
      Name : String (1 .. 6);
      Len  : Positive;
      Code : UTF8.Code_Point;
   end record;
   type Entity_Table is array (Positive range <>) of Entity;

   Entities : constant Entity_Table := (
      ("nbsp  ", 4, 16#A0#),
      ("iexcl ", 5, 16#A1#),
      ("cent  ", 4, 16#A2#),
      ("pound ", 5, 16#A3#),
      ("curren", 6, 16#A4#),
      ("yen   ", 3, 16#A5#),
      ("brvbar", 6, 16#A6#),
      ("sect  ", 4, 16#A7#),
      ("uml   ", 3, 16#A8#),
      ("copy  ", 4, 16#A9#),
      ("ordf  ", 4, 16#AA#),
      ("laquo ", 5, 16#AB#),
      ("not   ", 3, 16#AC#),
      ("shy   ", 3, 16#AD#),
      ("reg   ", 3, 16#AE#),
      ("macr  ", 4, 16#AF#),
      ("deg   ", 3, 16#B0#),
      ("plusmn", 6, 16#B1#),
      ("sup2  ", 4, 16#B2#),
      ("sup3  ", 4, 16#B3#),
      ("acute ", 5, 16#B4#),
      ("micro ", 5, 16#B5#),
      ("para  ", 4, 16#B6#),
      ("middot", 6, 16#B7#),
      ("cedil ", 5, 16#B8#),
      ("sup1  ", 4, 16#B9#),
      ("ordm  ", 4, 16#BA#),
      ("raquo ", 5, 16#BB#),
      ("frac14", 6, 16#BC#),
      ("frac12", 6, 16#BD#),
      ("frac34", 6, 16#BE#),
      ("iquest", 6, 16#BF#),
      ("Agrave", 6, 16#C0#),
      ("Aacute", 6, 16#C1#),
      ("Acirc ", 5, 16#C2#),
      ("Atilde", 6, 16#C3#),
      ("Auml  ", 4, 16#C4#),
      ("Aring ", 5, 16#C5#),
      ("AElig ", 5, 16#C6#),
      ("Ccedil", 6, 16#C7#),
      ("Egrave", 6, 16#C8#),
      ("Eacute", 6, 16#C9#),
      ("Ecirc ", 5, 16#CA#),
      ("Euml  ", 4, 16#CB#),
      ("Igrave", 6, 16#CC#),
      ("Iacute", 6, 16#CD#),
      ("Icirc ", 5, 16#CE#),
      ("Iuml  ", 4, 16#CF#),
      ("ETH   ", 3, 16#D0#),
      ("Ntilde", 6, 16#D1#),
      ("Ograve", 6, 16#D2#),
      ("Oacute", 6, 16#D3#),
      ("Ocirc ", 5, 16#D4#),
      ("Otilde", 6, 16#D5#),
      ("Ouml  ", 4, 16#D6#),
      ("times ", 5, 16#D7#),
      ("Oslash", 6, 16#D8#),
      ("Ugrave", 6, 16#D9#),
      ("Uacute", 6, 16#DA#),
      ("Ucirc ", 5, 16#DB#),
      ("Uuml  ", 4, 16#DC#),
      ("Yacute", 6, 16#DD#),
      ("THORN ", 5, 16#DE#),
      ("szlig ", 5, 16#DF#),
      ("agrave", 6, 16#E0#),
      ("aacute", 6, 16#E1#),
      ("acirc ", 5, 16#E2#),
      ("atilde", 6, 16#E3#),
      ("auml  ", 4, 16#E4#),
      ("aring ", 5, 16#E5#),
      ("aelig ", 5, 16#E6#),
      ("ccedil", 6, 16#E7#),
      ("egrave", 6, 16#E8#),
      ("eacute", 6, 16#E9#),
      ("ecirc ", 5, 16#EA#),
      ("euml  ", 4, 16#EB#),
      ("igrave", 6, 16#EC#),
      ("iacute", 6, 16#ED#),
      ("icirc ", 5, 16#EE#),
      ("iuml  ", 4, 16#EF#),
      ("eth   ", 3, 16#F0#),
      ("ntilde", 6, 16#F1#),
      ("ograve", 6, 16#F2#),
      ("oacute", 6, 16#F3#),
      ("ocirc ", 5, 16#F4#),
      ("otilde", 6, 16#F5#),
      ("ouml  ", 4, 16#F6#),
      ("divide", 6, 16#F7#),
      ("oslash", 6, 16#F8#),
      ("ugrave", 6, 16#F9#),
      ("uacute", 6, 16#FA#),
      ("ucirc ", 5, 16#FB#),
      ("uuml  ", 4, 16#FC#),
      ("yacute", 6, 16#FD#),
      ("thorn ", 5, 16#FE#),
      ("yuml  ", 4, 16#FF#),
      ("amp   ", 3, 16#26#),
      ("lt    ", 2, 16#3C#),
      ("gt    ", 2, 16#3E#),
      ("quot  ", 4, 16#22#),
      ("apos  ", 4, 16#27#),
      ("OElig ", 5, 16#152#),
      ("oelig ", 5, 16#153#),
      ("Scaron", 6, 16#160#),
      ("scaron", 6, 16#161#),
      ("Yuml  ", 4, 16#178#),
      ("fnof  ", 4, 16#192#),
      ("circ  ", 4, 16#2C6#),
      ("tilde ", 5, 16#2DC#),
      ("ensp  ", 4, 16#2002#),
      ("emsp  ", 4, 16#2003#),
      ("thinsp", 6, 16#2009#),
      ("zwnj  ", 4, 16#200C#),
      ("zwj   ", 3, 16#200D#),
      ("lrm   ", 3, 16#200E#),
      ("rlm   ", 3, 16#200F#),
      ("ndash ", 5, 16#2013#),
      ("mdash ", 5, 16#2014#),
      ("lsquo ", 5, 16#2018#),
      ("rsquo ", 5, 16#2019#),
      ("sbquo ", 5, 16#201A#),
      ("ldquo ", 5, 16#201C#),
      ("rdquo ", 5, 16#201D#),
      ("bdquo ", 5, 16#201E#),
      ("dagger", 6, 16#2020#),
      ("Dagger", 6, 16#2021#),
      ("bull  ", 4, 16#2022#),
      ("hellip", 6, 16#2026#),
      ("permil", 6, 16#2030#),
      ("prime ", 5, 16#2032#),
      ("Prime ", 5, 16#2033#),
      ("lsaquo", 6, 16#2039#),
      ("rsaquo", 6, 16#203A#),
      ("oline ", 5, 16#203E#),
      ("euro  ", 4, 16#20AC#),
      ("trade ", 5, 16#2122#),
      ("larr  ", 4, 16#2190#),
      ("rarr  ", 4, 16#2192#),
      ("minus ", 5, 16#2212#));

   Max_Entity : constant := 10;   --  longest "&...;" body looked at

   --  Decode the entity starting at Input (P) = '&'.  On success Code is its
   --  value and Next the index after the ';'.
   procedure Entity_At
     (Input : String;
      P     : Positive;
      Code  : out UTF8.Code_Point;
      Next  : out Positive;
      Ok    : out Boolean)
     with Pre => P in Input'Range
   is
      Semi  : Natural := 0;
      V     : UTF8.Code_Point := 0;
      Digit : Integer;
      First : Positive;
   begin
      Code := 0;
      Next := P;
      Ok := False;
      for K in P + 1 .. (if Input'Last - P > Max_Entity + 1
                         then P + Max_Entity + 1 else Input'Last)
      loop
         if Input (K) = ';' then
            Semi := K;
            exit;
         end if;
      end loop;
      if Semi <= P + 1 then
         return;
      end if;

      --  The body is Input (P + 1 .. Semi - 1).
      if Input (P + 1) = '#' then
         First := P + 2;
         if First < Semi and then (Input (First) = 'x' or else Input (First) = 'X')
         then
            First := First + 1;
            if First >= Semi then
               return;
            end if;
            for K in First .. Semi - 1 loop
               Digit :=
                 (case Input (K) is
                     when '0' .. '9' => Character'Pos (Input (K)) - 48,
                     when 'a' .. 'f' => Character'Pos (Input (K)) - 87,
                     when 'A' .. 'F' => Character'Pos (Input (K)) - 55,
                     when others     => -1);
               if Digit < 0 or else V > 16#10_FFFF# then
                  return;
               end if;
               V := V * 16 + UTF8.Code_Point (Digit);
            end loop;
         else
            if First >= Semi then
               return;
            end if;
            for K in First .. Semi - 1 loop
               if Input (K) not in '0' .. '9' or else V > 16#10_FFFF# then
                  return;
               end if;
               V := V * 10 + UTF8.Code_Point (Character'Pos (Input (K)) - 48);
            end loop;
         end if;
         Code := V;
         Ok := True;
      else
         for E of Entities loop
            if E.Len = Semi - P - 1
              and then E.Name (1 .. E.Len) = Input (P + 1 .. Semi - 1)
            then
               Code := E.Code;
               Ok := True;
               exit;
            end if;
         end loop;
      end if;
      if Ok then
         Next := (if Semi < Positive'Last then Semi + 1 else Semi);
      end if;
   end Entity_At;

   --  Element names, blank-padded.
   subtype Element_Name is String (1 .. 10);
   type Element_Names is array (Positive range <>) of Element_Name;

   function Lower (C : Character) return Character is
     (if C in 'A' .. 'Z'
      then Character'Val (Character'Pos (C) + 32) else C);

   --  Is Doc (Name) the blank-padded N, ignoring ASCII letter case?
   --  (Compared in place: this runs for every tag of a chapter.)
   function Matches (Doc : String; Name : Span; N : Element_Name) return Boolean
     with Pre => Within (Doc, Name) and then not Is_Empty (Name)
   is
      Len : constant Natural := Name.Last - Name.First + 1;
   begin
      if Len > N'Length or else (Len < N'Length and then N (Len + 1) /= ' ')
      then
         return False;
      end if;
      for K in 1 .. Len loop
         if Lower (Doc (Name.First + K - 1)) /= N (K) then
            return False;
         end if;
      end loop;
      return True;
   end Matches;

   --  Elements that end a paragraph (at their start and at their end).
   Blocks : constant Element_Names :=
     ("p         ", "div       ", "h1        ", "h2        ", "h3        ",
      "h4        ", "h5        ", "h6        ", "li        ", "dt        ",
      "dd        ", "br        ", "hr        ", "tr        ", "pre       ",
      "body      ", "table     ", "ul        ", "ol        ", "dl        ",
      "header    ", "footer    ", "aside     ", "figure    ", "center    ",
      "blockquote", "section   ", "article   ", "figcaption", "caption   ");

   --  Elements whose content is not reading text.
   Skipped : constant Element_Names :=
     ("head      ", "script    ", "style     ", "svg       ");

   function Is_One_Of
     (Doc : String; Name : Span; Names : Element_Names) return Boolean
     with Pre => Within (Doc, Name) and then not Is_Empty (Name)
   is
   begin
      for N of Names loop
         if Matches (Doc, Name, N) then
            return True;
         end if;
      end loop;
      return False;
   end Is_One_Of;

   --  An empty-element tag ("<br/>") has no content to skip.
   function Self_Closing (Doc : String; Tag : Span) return Boolean is
     (not Is_Empty (Tag) and then Doc (Tag.Last) = '/')
     with Pre => Within (Doc, Tag);

   function Is_Space (C : Character) return Boolean is
     (C = ' ' or else C = ASCII.HT or else C = ASCII.LF or else C = ASCII.CR);

   procedure Convert
     (Input  : String;
      Output : out String;
      Last   : out Natural)
   is
      P             : Positive := (if Input'Length > 0 then Input'First else 1);
      Tag           : Span;
      Name          : Span;
      Closing       : Boolean;
      Found         : Boolean;
      Pending_Space : Boolean := False;
      Pending_Break : Boolean := False;
      Skip_Depth    : Natural := 0;   --  nesting inside skipped elements
      Code          : UTF8.Code_Point;
      Next          : Positive;
      Ok            : Boolean;

      --  Emit the separator owed before the next piece of text.
      procedure Emit_Separator is
      begin
         if Last > 0 and then Last < Output'Last then
            if Pending_Break then
               if Output (Last) = ' ' then
                  Last := Last - 1;   --  no space before a break
               end if;
               Last := Last + 1;
               Output (Last) := Paragraph_Break;
            elsif Pending_Space and then Output (Last) /= Paragraph_Break then
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
      while P <= Input'Last and then Last < Output'Last loop
         if Input (P) = '<' then
            Next_Tag (Input, P, Tag, Found);
            exit when not Found;
            Tag_Name (Input, Tag, Name, Closing);
            if Is_Empty (Name) then
               null;
            elsif Is_One_Of (Input, Name, Skipped) then
               if Closing then
                  if Skip_Depth > 0 then
                     Skip_Depth := Skip_Depth - 1;
                  end if;
               elsif not Self_Closing (Input, Tag) and then Skip_Depth < Natural'Last
               then
                  Skip_Depth := Skip_Depth + 1;
               end if;
            elsif Is_One_Of (Input, Name, Blocks) then
               Pending_Break := True;
            end if;
            --  Next_Tag moved P past the tag.
         elsif Skip_Depth > 0 then
            P := P + 1;
         elsif Is_Space (Input (P)) then
            Pending_Space := True;
            P := P + 1;
         elsif Input (P) = '&' then
            Entity_At (Input, P, Code, Next, Ok);
            if Ok then
               if Code /= 0 then
                  Emit_Separator;
                  UTF8.Append (Output, Last, Code);
               end if;
               P := Next;
            else
               Emit_Separator;
               if Last < Output'Last then
                  Last := Last + 1;
                  Output (Last) := '&';
               end if;
               P := P + 1;
            end if;
         else
            Emit_Separator;
            --  Copy the run of ordinary characters up to the next markup,
            --  entity or space in one go.
            declare
               E : Natural := P;
            begin
               while E < Input'Last
                 and then E - P < Output'Last - Last - 1
                 and then Input (E + 1) /= '<'
                 and then Input (E + 1) /= '&'
                 and then not Is_Space (Input (E + 1))
               loop
                  E := E + 1;
               end loop;
               if Last < Output'Last then
                  Output (Last + 1 .. Last + 1 + (E - P)) := Input (P .. E);
                  Last := Last + 1 + (E - P);
               end if;
               P := E + 1;
            end;
         end if;
         exit when P = Positive'Last;
      end loop;
      --  No trailing space.
      if Last > 0 and then Output (Last) = ' ' then
         Last := Last - 1;
      end if;
   end Convert;
end Xhtml_Text;
