with Language_Guess;
with Page_Layout;
with Reader_View;
with Text_Metrics;

package body Reader is
   use type Books.Status;

   type Offset_Array_Access is access Page_Layout.Offset_Array;

   Starts : constant Offset_Array_Access :=
     new Page_Layout.Offset_Array (1 .. Max_Pages);

   Book    : Books.Book;
   Opened  : Boolean := False;
   Font    : Truetype.Font;
   --  On the heap: the kerning tables make it large.
   type Metrics_Access is access Text_Metrics.Table;
   Metrics_Ref : constant Metrics_Access := new Text_Metrics.Table;
   Metrics : Text_Metrics.Table renames Metrics_Ref.all;
   Geo     : Page_Layout.Geometry;

   Current : Natural := 0;             --  chapter
   Loaded  : Books.Status := Books.OK; --  how loading it went
   Pages   : Natural := 0;             --  0: no text, or it failed
   Shown   : Natural := 0;             --  page

   --  The book's language from its metadata, and the current chapter's.
   Max_Tag   : constant := 35;
   Meta_Tag  : String (1 .. Max_Tag);
   Meta_Last : Natural := 0;
   Lang_Tag  : String (1 .. Max_Tag);
   Lang_Last : Natural := 0;

   function Text_Last return Natural is (Books.Text_Last (Book));

   procedure Set_Language (Tag : String) is
      N : constant Natural := Natural'Min (Tag'Length, Max_Tag);
   begin
      Lang_Tag (1 .. N) := Tag (Tag'First .. Tag'First + N - 1);
      Lang_Last := N;
   end Set_Language;

   --  Pick the language of the chapter just loaded (see the spec) and its
   --  patterns.
   procedure Choose_Language (V : in out FS.Volume) is
      use type Language_Guess.Language;
      G    : constant Language_Guess.Language :=
        Language_Guess.Guess (Books.Text (Book) (1 .. Text_Last));
      Code : constant String := Language_Guess.Code (G);
      Meta : String renames Meta_Tag (1 .. Meta_Last);
   begin
      if G /= Language_Guess.Unknown then
         --  Keep the metadata's region ("en-GB") when it agrees.
         if Meta_Last >= 2 and then Meta (1 .. 2) = Code
           and then (Meta_Last = 2 or else Meta (3) in '-' | '_')
         then
            Set_Language (Meta);
         else
            Set_Language (Code);
         end if;
      end if;
      Hyphens.Select_Language (V, Lang_Tag (1 .. Lang_Last), Geo.Hyph);
   end Choose_Language;

   --  Load chapter C and lay it out.
   procedure Load (V : in out FS.Volume; C : Positive) is
      Complete : Boolean;
   begin
      Books.Load (V, Book, C, Loaded);
      Current := C;
      Pages := 0;
      Shown := 1;
      if Loaded = Books.OK and then Text_Last > 0 then
         Choose_Language (V);
         Page_Layout.Paginate
           (Metrics, Font, Geo, Books.Text (Book) (1 .. Text_Last),
            Starts.all, Pages, Complete);
      end if;
   end Load;

   --  Something to show: text, or the reason there is none.
   function Showable return Boolean is
     (Pages > 0 or else Loaded /= Books.OK);

   --  From chapter C on, in direction Step, load the first showable
   --  chapter.  Found is False, with Current's contents undefined, when
   --  there is none.
   procedure Seek
     (V : in out FS.Volume; C : Positive; Step : Integer; Found : out Boolean)
   is
      I : Integer := C;
   begin
      Found := False;
      while I in 1 .. Books.Chapter_Count (Book) loop
         Load (V, I);
         if Showable then
            Found := True;
            return;
         end if;
         I := I + Step;
      end loop;
   end Seek;

   procedure Open
     (V      : in out FS.Volume;
      Name   : String;
      F      : Truetype.Font;
      Size   : Positive;
      At_Pos : Position;
      Result : out Books.Status)
   is
      Found : Boolean;
   begin
      Close;
      Books.Open (V, Name, Book, Result);
      if Result /= Books.OK then
         return;
      end if;
      if Books.Chapter_Count (Book) = 0 then
         Books.Close (Book);
         Result := Books.Not_A_Book;
         return;
      end if;
      declare
         Meta : constant String := Books.Language (Book);
         N    : constant Natural := Natural'Min (Meta'Length, Max_Tag);
      begin
         Meta_Tag (1 .. N) := Meta (Meta'First .. Meta'First + N - 1);
         Meta_Last := N;
         Set_Language (Meta_Tag (1 .. N));
      end;
      Font := F;
      Text_Metrics.Prepare (Metrics, F, Size);
      Geo := Page_Layout.Make
        (Metrics, F, Reader_View.Col_Width, Reader_View.Area_Height);

      if At_Pos.Chapter in 1 .. Books.Chapter_Count (Book) then
         Seek (V, At_Pos.Chapter, 1, Found);
         if Found and then Current = At_Pos.Chapter and then Pages > 0 then
            Shown := Page_Layout.Page_Of (Starts.all, Pages, At_Pos.Offset);
         end if;
      else
         Seek (V, 1, 1, Found);
      end if;
      if not Found then
         --  No chapter has any text: show the first one's emptiness.
         Load (V, 1);
      end if;
      Opened := True;
   end Open;

   procedure Close is
   begin
      if Opened then
         Books.Close (Book);
         Opened := False;
      end if;
      Current := 0;
      Pages := 0;
      Shown := 0;
   end Close;

   function Is_Open return Boolean is (Opened);

   procedure Next_Page (V : in out FS.Volume; Moved : out Boolean) is
      Was_Chapter : constant Natural := Current;
      Was_Page    : constant Natural := Shown;
   begin
      Moved := True;
      if Shown < Pages then
         Shown := Shown + 1;
         return;
      end if;
      if Current < Books.Chapter_Count (Book) then
         Seek (V, Current + 1, 1, Moved);
      else
         Moved := False;
      end if;
      if not Moved and then Current /= Was_Chapter then
         Load (V, Was_Chapter);
         Shown := Was_Page;
      end if;
   end Next_Page;

   procedure Prev_Page (V : in out FS.Volume; Moved : out Boolean) is
      Was_Chapter : constant Natural := Current;
      Was_Page    : constant Natural := Shown;
   begin
      Moved := True;
      if Shown > 1 then
         Shown := Shown - 1;
         return;
      end if;
      if Current > 1 then
         Seek (V, Current - 1, -1, Moved);
      else
         Moved := False;
      end if;
      if Moved then
         Shown := Natural'Max (1, Pages);
      elsif Current /= Was_Chapter then
         Load (V, Was_Chapter);
         Shown := Was_Page;
      end if;
   end Prev_Page;

   function Where return Position is
     ((Chapter => Current,
       Offset  => (if Pages > 0 then Starts (Shown) else 1)));

   function Language return String is (Lang_Tag (1 .. Lang_Last));
   function Chapter return Natural is (Current);
   function Chapter_Count return Natural is
     (if Opened then Books.Chapter_Count (Book) else 0);
   function Page return Natural is (Shown);
   function Page_Count return Natural is (Pages);

   procedure Draw
     (Fr    : in out Mono_Frame.Frame;
      UI    : Truetype.Font;
      Title : String;
      Batt  : Status_Bar.Battery;
      Menu  : Boolean := False) is
   begin
      if Pages > 0 then
         Reader_View.Draw_Page
           (Fr, UI, Font, Metrics, Geo, Books.Text (Book) (1 .. Text_Last),
            Starts (Shown), Title, Batt, Shown, Pages);
      elsif Loaded /= Books.OK then
         Reader_View.Draw_Message
           (Fr, UI, Title, Batt, "Chapter could not be read: "
            & Loaded'Image);
      else
         Reader_View.Draw_Message (Fr, UI, Title, Batt, "No text");
      end if;
      if Menu then
         Reader_View.Draw_Menu
           (Fr, UI, Current, Chapter_Count, Shown, Pages);
      end if;
   end Draw;

end Reader;
