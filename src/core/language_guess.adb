package body Language_Guess
  with SPARK_Mode => On
is
   subtype Known is Language range English .. Russian;

   --  Each language's words, space-separated with a space at either end.
   --  Words two languages share ("la", "de", "en", ...) are left out.
   English_Words : constant String :=
     " the and of to that was his with for you he it is ";
   German_Words  : constant String :=
     " der die und das nicht sich ist den mit ein eine auch dem sie ich er"
     & " zu ";
   French_Words  : constant String :=
     " le les et des une est dans qui pas pour sur au du ce ne je ";
   Spanish_Words : constant String :=
     " el los las y del por para se lo su al ";
   Italian_Words : constant String :=
     " che di non per sono della gli nel è ";
   Dutch_Words   : constant String :=
     " het een van niet zijn dat op wat ze ";
   Russian_Words : constant String :=
     " и в не на что он с как это по но я ";

   --  Is Text (First .. Last), lower-cased, one of List's words?
   function In_List (List : String; Text : String; First, Last : Positive)
     return Boolean
     with Pre => First <= Last and then Last <= Text'Last
                 and then First >= Text'First
   is
      Len : constant Positive := Last - First + 1;
      Ok  : Boolean;
   begin
      for P in List'First + 1 .. List'Last - Len loop
         if List (P - 1) = ' ' and then List (P + Len) = ' ' then
            Ok := True;
            for K in 0 .. Len - 1 loop
               declare
                  C : Character := Text (First + K);
               begin
                  if C in 'A' .. 'Z' then
                     C := Character'Val (Character'Pos (C) + 32);
                  end if;
                  if List (P + K) /= C then
                     Ok := False;
                     exit;
                  end if;
               end;
            end loop;
            if Ok then
               return True;
            end if;
         end if;
      end loop;
      return False;
   end In_List;

   --  A byte that is part of a word: an ASCII letter, or any byte of a
   --  multi-byte UTF-8 sequence (accented, Greek, Cyrillic letters).
   function Word_Byte (C : Character) return Boolean is
     (C in 'a' .. 'z' or else C in 'A' .. 'Z' or else C >= Character'Val (128));

   function Guess (Text : String) return Language is
      Last  : constant Natural :=
        (if Text'Length > Sample then Text'First + Sample - 1 else Text'Last);
      Hits  : array (Known) of Natural := (others => 0);
      P     : Natural := Text'First;
      Start : Positive;
      Best, Second : Natural := 0;
      Winner : Language := Unknown;
   begin
      while P <= Last loop
         if Word_Byte (Text (P)) then
            Start := P;
            while P < Last and then Word_Byte (Text (P + 1)) loop
               P := P + 1;
            end loop;
            if P - Start < 8 then
               for L in Known loop
                  if In_List
                       ((case L is
                           when English => English_Words,
                           when German  => German_Words,
                           when French  => French_Words,
                           when Spanish => Spanish_Words,
                           when Italian => Italian_Words,
                           when Dutch   => Dutch_Words,
                           when Russian => Russian_Words),
                        Text, Start, P)
                    and then Hits (L) < Natural'Last
                  then
                     Hits (L) := Hits (L) + 1;
                  end if;
               end loop;
            end if;
         end if;
         exit when P = Natural'Last;
         P := P + 1;
      end loop;

      for L in Known loop
         if Hits (L) > Best then
            Second := Best;
            Best := Hits (L);
            Winner := L;
         elsif Hits (L) > Second then
            Second := Hits (L);
         end if;
      end loop;
      if Best >= Min_Hits and then Best >= 2 * Second then
         return Winner;
      end if;
      return Unknown;
   end Guess;

   function Code (L : Language) return String is
     (case L is
         when Unknown => "",
         when English => "en",
         when German  => "de",
         when French  => "fr",
         when Spanish => "es",
         when Italian => "it",
         when Dutch   => "nl",
         when Russian => "ru");

end Language_Guess;
