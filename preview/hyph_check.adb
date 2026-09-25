--  Exercise Hyphenation on the host:
--
--    hyph_check PATTERNS LEFT RIGHT < WORDS
--
--  builds the trie from a hyph-utf8 pattern file (hyph-XX.pat.txt) with
--  LEFT / RIGHT letters kept either side of a break, then prints every
--  word of standard input (one per line) with its hyphenation points as
--  '-', and the build and hyphenation times.
with Ada.Calendar; use Ada.Calendar;
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Direct_IO;
with Ada.Directories;
with Ada.Text_IO; use Ada.Text_IO;

with Hyphenation;
with UTF8;

procedure Hyph_Check is
   Path : constant String := Argument (1);
   Size : constant Natural := Natural (Ada.Directories.Size (Path));

   subtype Contents is String (1 .. Size);
   package Content_IO is new Ada.Direct_IO (Contents);

   type Text_Access is access Contents;
   Text : constant Text_Access := new Contents;

   Nodes, Pool : Natural;
   T0          : Time := Clock;
   Build_T     : Duration;
   Word_T      : Duration := 0.0;
   Words       : Natural := 0;
   Ok          : Boolean;
begin
   declare
      F : Content_IO.File_Type;
   begin
      Content_IO.Open (F, Content_IO.In_File, Path);
      Content_IO.Read (F, Text.all);
      Content_IO.Close (F);
   end;

   Hyphenation.Measure (Text.all, Nodes, Pool);
   declare
      type Trie_Access is access Hyphenation.Trie;
      T : constant Trie_Access := new Hyphenation.Trie (Nodes, Pool);
   begin
      Hyphenation.Build
        (Text.all, Positive'Value (Argument (2)), Positive'Value (Argument (3)),
         T.all, Ok);
      Build_T := Clock - T0;
      Put_Line (Standard_Error,
                "nodes" & Nodes'Image & " (used" & T.Used'Image & "), pool"
                & Pool'Image & ", letters" & T.Alphabet'Image & ", ok "
                & Ok'Image & "," & Duration'Image (Build_T * 1000) & " ms");

      while not End_Of_File loop
         declare
            Line  : constant String := Get_Line;
            Word  : Hyphenation.Code_Array (1 .. Hyphenation.Max_Word);
            Ends  : array (1 .. Hyphenation.Max_Word) of Natural;
            N     : Natural := 0;
            P     : Positive := 1;
            From  : Positive := 1;
            C     : UTF8.Code_Point;
         begin
            while P <= Line'Last and then N < Hyphenation.Max_Word loop
               UTF8.Next_Code (Line, P, C);
               N := N + 1;
               Word (N) := C;
               Ends (N) := P - 1;
            end loop;
            declare
               Breaks : Hyphenation.Break_Array (1 .. N);
            begin
               T0 := Clock;
               Hyphenation.Hyphenate (T.all, Word (1 .. N), Breaks);
               Word_T := Word_T + (Clock - T0);
               Words := Words + 1;
               for I in 1 .. N loop
                  Put (Line (From .. Ends (I)));
                  From := Ends (I) + 1;
                  if I < N and then Breaks (I) then
                     Put ("-");
                  end if;
               end loop;
               New_Line;
            end;
         end;
      end loop;
      if Words > 0 then
         Put_Line (Standard_Error,
                   Words'Image & " words," & Duration'Image
                     (Word_T * 1_000_000 / Words) & " us a word");
      end if;
   end;
end Hyph_Check;
