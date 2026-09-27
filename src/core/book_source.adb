with Ada.Unchecked_Deallocation;
with Interfaces; use Interfaces;

with Deflate;
with Inflate;
with Inflate.CRC32;
with Plain_Text;
with Xhtml_Text;
with Xml_Scan;
with Zip;

package body Book_Source is
   use type Bytes.Byte_Array_Access;
   use type Shelf.Book_Format;

   procedure Free is new Ada.Unchecked_Deallocation
     (Bytes.Byte_Array, Bytes.Byte_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (String, String_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Opf.Span_Array, Span_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Index_Array, Index_Array_Access);

   procedure Free is new Ada.Unchecked_Deallocation
     (Xhtml_Text.Anchor_Array, Anchor_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Toc.Line_Array, Line_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Target_Array, Target_Array_Access);

   type Item_Array_Access is access Opf.Item_Array;
   procedure Free is new Ada.Unchecked_Deallocation
     (Opf.Item_Array, Item_Array_Access);

   --  Make Buf hold at least N bytes (N >= 1), keeping it if it does.
   procedure Reserve (Buf : in out Bytes.Byte_Array_Access; N : Positive) is
   begin
      if Buf = null or else Buf'Length < N then
         Free (Buf);
         Buf := new Bytes.Byte_Array (0 .. N - 1);
      end if;
   end Reserve;

   procedure Reserve (Buf : in out String_Access; N : Positive) is
   begin
      if Buf = null or else Buf'Length < N then
         Free (Buf);
         Buf := new String (1 .. N);
      end if;
   end Reserve;

   procedure Close (B : in out Book) is
   begin
      Free (B.Dir);
      Free (B.Opf_Path);
      Free (B.Opf_Doc);
      Free (B.Spine);
      Free (B.Whole);
      Free (B.Starts);
      Free (B.Packed);
      Free (B.Member);
      Free (B.Text);
      Free (B.Anchors);
      Free (B.Lines);
      Free (B.Labels);
      Free (B.Targets);
      B.Format := Shelf.Unknown;
      B.Lang := (First => 1, Last => 0);
      B.Nav_Href := (First => 1, Last => 0);
      B.Ncx_Href := (First => 1, Last => 0);
      B.Anchor_Count := 0;
      B.Entries := 0;
      B.Chapters := 0;
      B.Member_Size := 0;
      B.Text_Last := 0;
   end Close;

   --  Read Into'Length bytes of B.File from Offset; all or nothing.
   procedure Read_Exact
     (V      : in out FS.Volume;
      B      : in out Book;
      Offset : Unsigned_32;
      Into   : out Bytes.Byte_Array;
      Result : out Status)
   is
      Count   : Natural;
      Read_Ok : Boolean;
   begin
      FS.Read (V, B.File, Offset, Into, Count, Read_Ok);
      Result := (if not Read_Ok then Read_Error
                 elsif Count /= Into'Length then Not_A_Book
                 else OK);
   end Read_Exact;

   --  Inflate the archive member Path into B.Member (0 .. B.Member_Size - 1)
   --  and check its CRC.
   procedure Extract
     (V      : in out FS.Volume;
      B      : in out Book;
      Path   : String;
      Result : out Status)
   is
      M      : Zip.Member;
      Found  : Boolean;
      Header : Bytes.Byte_Array (0 .. Zip.Local_Header_Size - 1);
      Start  : Unsigned_32;
      Size   : Natural;
      Packed : Natural;
   begin
      B.Member_Size := 0;
      Zip.Find (B.Dir.all, Path, M, Found);
      if not Found then
         Result := Not_Found;
         return;
      elsif M.Method /= Zip.Stored and then M.Method /= Zip.Deflated then
         Result := Unsupported;
         return;
      elsif M.Size > Max_Chapter
        or else (M.Method = Zip.Deflated and then M.Compressed > Max_Chapter)
      then
         Result := Too_Big;
         return;
      end if;
      Size := Natural (M.Size);
      Packed := Natural (M.Compressed);

      Read_Exact (V, B, M.Header_Offset, Header, Result);
      if Result /= OK then
         return;
      end if;
      Zip.Data_Offset (Header, M, Start, Found);
      if not Found then
         Result := Not_A_Book;
         return;
      end if;

      Reserve (B.Member, Natural'Max (Size, 1));
      if Size = 0 then
         Result := OK;
         return;
      end if;

      if M.Method = Zip.Stored then
         Read_Exact (V, B, Start, B.Member (0 .. Size - 1), Result);
      elsif Packed = 0 then
         Result := Bad_Data;
      else
         Reserve (B.Packed, Packed);
         Read_Exact (V, B, Start, B.Packed (0 .. Packed - 1), Result);
         if Result = OK then
            declare
               Valid : Boolean;
            begin
               Deflate.Decode
                 (B.Packed (0 .. Packed - 1), B.Member (0 .. Size - 1), Valid);
               if not Valid then
                  Result := Bad_Data;
               end if;
            end;
         end if;
      end if;
      if Result /= OK then
         return;
      end if;

      declare
         Data : Inflate.Byte_Array (1 .. Size)
           with Import, Address => B.Member (0)'Address;
      begin
         if Unsigned_32 (Inflate.CRC32.Compute (Data)) /= M.CRC then
            Result := Bad_Data;
            return;
         end if;
      end;
      B.Member_Size := Size;
      Result := OK;
   end Extract;

   --  A copy of the extracted member as a String.
   function Member_Text (B : Book) return String_Access is
      Doc : String (1 .. B.Member_Size)
        with Import, Address => B.Member (0)'Address;
   begin
      return new String'(Doc);
   end Member_Text;

   procedure Open_Epub (V : in out FS.Volume; B : in out Book; Result : out Status) is
      Size : constant Unsigned_32 := FS.Size (B.File);
      Tail_Length : constant Natural :=
        Natural (Unsigned_32'Min (Size, Zip.Tail_Size));
      Dir : Zip.Directory;
      Found : Boolean;
   begin
      --  The central directory, found from the end-of-directory record.
      if Tail_Length < 22 then
         Result := Not_A_Book;
         return;
      end if;
      Reserve (B.Packed, Tail_Length);
      Read_Exact (V, B, Size - Unsigned_32 (Tail_Length),
                  B.Packed (0 .. Tail_Length - 1), Result);
      if Result /= OK then
         return;
      end if;
      Zip.Find_Directory (B.Packed (0 .. Tail_Length - 1), Size, Dir, Found);
      if not Found or else Dir.Size = 0 then
         Result := Not_A_Book;
         return;
      end if;
      B.Dir := new Bytes.Byte_Array (0 .. Natural (Dir.Size) - 1);
      Read_Exact (V, B, Dir.Offset, B.Dir.all, Result);
      if Result /= OK then
         return;
      end if;

      --  container.xml names the OPF.
      Extract (V, B, Opf.Container_Path, Result);
      if Result /= OK then
         Result := (if Result = Not_Found then Not_A_Book else Result);
         return;
      end if;
      declare
         Container : String (1 .. B.Member_Size)
           with Import, Address => B.Member (0)'Address;
         Root : constant Xml_Scan.Span := Opf.Rootfile (Container);
      begin
         if Xml_Scan.Is_Empty (Root) then
            Result := Not_A_Book;
            return;
         end if;
         B.Opf_Path := new String'(Xml_Scan.Text (Container, Root));
      end;

      Extract (V, B, B.Opf_Path.all, Result);
      if Result /= OK then
         Result := (if Result = Not_Found then Not_A_Book else Result);
         return;
      end if;
      B.Opf_Doc := Member_Text (B);
      B.Lang := Opf.Language (B.Opf_Doc.all);

      declare
         Doc   : String renames B.Opf_Doc.all;
         Items : Item_Array_Access :=
           new Opf.Item_Array (1 .. Natural'Max (Opf.Count_Items (Doc), 1));
         Item_Count : Natural;
      begin
         Opf.Read_Manifest (Doc, Items.all, Item_Count);
         Opf.Toc_Hrefs (Items (1 .. Item_Count), B.Nav_Href, B.Ncx_Href);
         B.Spine := new Opf.Span_Array
           (1 .. Natural'Max (Opf.Count_Itemrefs (Doc), 1));
         Opf.Read_Spine (Doc, Items (1 .. Item_Count), B.Spine.all, B.Chapters);
         Free (Items);
      end;
      Result := (if B.Chapters = 0 then Not_A_Book else OK);
   end Open_Epub;

   procedure Open_Text (V : in out FS.Volume; B : in out Book; Result : out Status) is
      Size : constant Unsigned_32 := FS.Size (B.File);
      Last : Natural;
      Count : Natural := 0;
      From  : Positive;
   begin
      if Size > Max_Text_File then
         Result := Too_Big;
         return;
      end if;
      Reserve (B.Packed, Natural'Max (Natural (Size), 1));
      Read_Exact (V, B, 0, B.Packed (0 .. Natural (Size) - 1), Result);
      if Result /= OK then
         return;
      end if;
      declare
         Raw : Bytes.Byte_Array renames B.Packed (0 .. Natural (Size) - 1);
      begin
         B.Whole := new String (1 .. Natural'Max (Plain_Text.Output_Bound (Raw), 1));
         Plain_Text.Normalize (Raw, B.Whole.all, Last);
      end;
      Free (B.Packed);   --  the raw file is no longer needed

      --  Cut the text into sections: count them, then record the starts.
      for Pass in 1 .. 2 loop
         From := 1;
         Count := 0;
         while From <= Last loop
            Count := Count + 1;
            if Pass = 2 then
               B.Starts (Count) := From;
            end if;
            From := Plain_Text.Section_End (B.Whole (1 .. Last), From, Section_Size) + 1;
         end loop;
         if Pass = 1 then
            B.Starts := new Index_Array (1 .. Count + 1);
         end if;
      end loop;
      B.Starts (Count + 1) := Last + 1;
      B.Chapters := Count;
      Result := (if Count = 0 then Not_A_Book else OK);
   end Open_Text;

   procedure Open
     (V      : in out FS.Volume;
      Name   : String;
      B      : in out Book;
      Result : out Status)
   is
      Found : Boolean;
   begin
      Close (B);
      FS.Open (V, Books_Folder & "/" & Name, B.File, Found);
      if not Found then
         Result := Not_Found;
         return;
      end if;
      B.Format := Shelf.Format_Of (Name);
      case B.Format is
         when Shelf.EPUB    => Open_Epub (V, B, Result);
         when Shelf.TXT     => Open_Text (V, B, Result);
         when Shelf.Unknown => Result := Not_A_Book;
      end case;
      if Result /= OK then
         Close (B);
      end if;
   end Open;

   procedure Load
     (V      : in out FS.Volume;
      B      : in out Book;
      I      : Positive;
      Result : out Status)
   is
   begin
      B.Text_Last := 0;
      B.Anchor_Count := 0;
      if B.Format = Shelf.TXT then
         declare
            First : constant Positive := B.Starts (I);
            Last  : constant Natural := B.Starts (I + 1) - 1;
         begin
            Reserve (B.Text, Natural'Max (Last - First + 1, 1));
            B.Text (1 .. Last - First + 1) := B.Whole (First .. Last);
            B.Text_Last := Last - First + 1;
            Result := OK;
         end;
         return;
      end if;

      declare
         Path    : String (1 .. 1024);
         Last    : Natural;
         Path_Ok : Boolean;
      begin
         Opf.Resolve (B.Opf_Path.all, Xml_Scan.Text (B.Opf_Doc.all, B.Spine (I)),
                      Path, Last, Path_Ok);
         if not Path_Ok then
            Result := Not_Found;
            return;
         end if;
         Extract (V, B, Path (1 .. Last), Result);
      end;
      if Result /= OK then
         return;
      end if;
      Reserve (B.Text, Natural'Max (B.Member_Size, 1));
      if B.Anchors = null then
         B.Anchors := new Xhtml_Text.Anchor_Array (1 .. Max_Anchors);
      end if;
      declare
         Doc : String (1 .. B.Member_Size)
           with Import, Address => B.Member (0)'Address;
      begin
         Xhtml_Text.Convert
           (Doc, B.Text (1 .. B.Member_Size), B.Text_Last,
            B.Anchors.all, B.Anchor_Count);
      end;
   end Load;

   function Anchor_Offset
     (B : Book; Hash : Interfaces.Unsigned_32) return Natural is
   begin
      for K in 1 .. B.Anchor_Count loop
         if B.Anchors (K).Hash = Hash then
            return B.Anchors (K).Offset;
         end if;
      end loop;
      return 0;
   end Anchor_Offset;

   --  The hash of the archive path Href leads to from the document at
   --  Base, or 0 (Ok False) if it does not resolve.
   procedure Path_Hash
     (Base : String;
      Href : String;
      Hash : out Unsigned_32;
      Ok   : out Boolean)
   is
      Path : String (1 .. 1024);
      Last : Natural;
   begin
      Opf.Resolve (Base, Href, Path, Last, Ok);
      Hash := (if Ok then Xhtml_Text.Id_Hash (Path (1 .. Last)) else 0);
   end Path_Hash;

   --  One entry per chapter, "Chapter N": for a book without a usable
   --  table of contents.
   procedure Contents_From_Spine (B : in out Book) is
      Last : Natural := 0;
   begin
      B.Lines := new Toc.Line_Array (1 .. B.Chapters);
      B.Targets := new Target_Array (1 .. B.Chapters);
      B.Labels := new String (1 .. B.Chapters * 16);
      for I in 1 .. B.Chapters loop
         declare
            N     : constant String := Positive'Image (I);
            Label : constant String := "Chapter" & N;
         begin
            B.Labels (Last + 1 .. Last + Label'Length) := Label;
            B.Lines (I) := (Level => 1, First => Last + 1,
                            Last => Last + Label'Length);
            B.Targets (I) := (Chapter => I, others => <>);
            Last := Last + Label'Length;
         end;
      end loop;
      B.Entries := B.Chapters;
   end Contents_From_Spine;

   --  Read the table of contents from the nav document (Is_Nav) or NCX
   --  at Href, into B.Lines etc.; B.Entries = 0 and nothing allocated if
   --  it gives no entries.
   procedure Read_Contents
     (V      : in out FS.Volume;
      B      : in out Book;
      Href   : Xml_Scan.Span;
      Is_Nav : Boolean)
   is
      Result : Status;
      Path   : String (1 .. 1024);
      Last   : Natural;
      Path_Ok     : Boolean;
   begin
      B.Entries := 0;
      if Xml_Scan.Is_Empty (Href) then
         return;
      end if;
      Opf.Resolve (B.Opf_Path.all, Xml_Scan.Text (B.Opf_Doc.all, Href),
                   Path, Last, Path_Ok);
      if Path_Ok then
         Extract (V, B, Path (1 .. Last), Result);
      end if;
      if not Path_Ok or else Result /= OK or else B.Member_Size = 0 then
         return;
      end if;

      declare
         type Item_Array_Access is access Toc.Item_Array;
         procedure Free is new Ada.Unchecked_Deallocation
           (Toc.Item_Array, Item_Array_Access);
         type Hash_Array is array (Positive range <>) of Unsigned_32;
         type Hash_Array_Access is access Hash_Array;
         procedure Free is new Ada.Unchecked_Deallocation
           (Hash_Array, Hash_Array_Access);

         Doc_Path : constant String := Path (1 .. Last);
         Doc      : String (1 .. B.Member_Size)
           with Import, Address => B.Member (0)'Address;
         Items    : Item_Array_Access := new Toc.Item_Array
           (1 .. Natural'Max (Toc.Count_Links (Doc, Is_Nav), 1));
         Count    : Natural;
         --  The hash of each chapter's archive path (0 if it does not
         --  resolve).
         Spine    : Hash_Array_Access := new Hash_Array (1 .. B.Chapters);
         Room      : Natural := 0;   --  for all the labels
         Max_Label : Natural := 0;
         Min_Level : Toc.Level_Type := Toc.Max_Level;
         Next      : Natural := 0;   --  where to start looking in Spine
         Tmp       : String_Access;
         N         : Natural := 0;   --  entries kept
         Used      : Natural := 0;   --  of B.Labels
      begin
         Toc.Read (Doc, Is_Nav, Items.all, Count);
         for I in 1 .. B.Chapters loop
            Path_Hash (B.Opf_Path.all,
                       Xml_Scan.Text (B.Opf_Doc.all, B.Spine (I)),
                       Spine (I), Path_Ok);
         end loop;
         for I in 1 .. Count loop
            declare
               Len : constant Natural :=
                 Items (I).Label.Last - Items (I).Label.First + 1;
            begin
               if Len > 0 then
                  Room := Room + Len;
                  Max_Label := Natural'Max (Max_Label, Len);
               end if;
               Room := Room + 16;   --  "Chapter N" for an empty label
            end;
         end loop;
         B.Lines := new Toc.Line_Array (1 .. Natural'Max (Count, 1));
         B.Targets := new Target_Array (1 .. Natural'Max (Count, 1));
         B.Labels := new String (1 .. Natural'Max (Room, 1));
         Tmp := new String (1 .. Natural'Max (Max_Label, 16));

         for I in 1 .. Count loop
            declare
               It      : constant Toc.Item := Items (I);
               Href    : constant String := Xml_Scan.Text (Doc, It.Href);
               Sharp   : Natural := 0;
               H       : Unsigned_32;
               Chapter : Natural := 0;
               T_Last  : Natural := 0;
               J       : Positive;
            begin
               for K in Href'Range loop
                  if Href (K) = '#' then
                     Sharp := K;
                     exit;
                  end if;
               end loop;
               --  The file (Resolve drops the fragment), searched from the
               --  previous entry's chapter on: entries mostly follow the
               --  spine.
               Path_Hash (Doc_Path, Href, H, Path_Ok);
               if Path_Ok then
                  for K in 0 .. B.Chapters - 1 loop
                     J := (Next + K) mod B.Chapters + 1;
                     if Spine (J) = H then
                        Chapter := J;
                        Next := J - 1;
                        exit;
                     end if;
                  end loop;
               end if;

               if Chapter /= 0 then
                  if not Xml_Scan.Is_Empty (It.Label) then
                     Xhtml_Text.Convert
                       (Doc (It.Label.First .. It.Label.Last),
                        Tmp (1 .. It.Label.Last - It.Label.First + 1),
                        T_Last);
                     for K in 1 .. T_Last loop
                        if Tmp (K) = Xhtml_Text.Paragraph_Break then
                           Tmp (K) := ' ';
                        end if;
                     end loop;
                  end if;
                  if T_Last = 0 then
                     declare
                        Label : constant String :=
                          "Chapter" & Positive'Image (Chapter);
                     begin
                        T_Last := Label'Length;
                        Tmp (1 .. T_Last) := Label;
                     end;
                  end if;
                  N := N + 1;
                  B.Labels (Used + 1 .. Used + T_Last) := Tmp (1 .. T_Last);
                  B.Lines (N) := (Level => It.Level, First => Used + 1,
                                  Last => Used + T_Last);
                  Used := Used + T_Last;
                  B.Targets (N) :=
                    (Chapter    => Chapter,
                     Has_Anchor => Sharp in Href'First .. Href'Last - 1,
                     Anchor     =>
                       (if Sharp in Href'First .. Href'Last - 1
                        then Xhtml_Text.Id_Hash (Href (Sharp + 1 .. Href'Last))
                        else 0));
                  Min_Level := Toc.Level_Type'Min (Min_Level, It.Level);
               end if;
            end;
         end loop;

         --  A toc nested one level deeper than it needs (an outer list
         --  around everything) starts at level 1 all the same.
         for I in 1 .. N loop
            B.Lines (I).Level := B.Lines (I).Level - (Min_Level - 1);
         end loop;
         B.Entries := N;
         Free (Items);
         Free (Spine);
         Free (Tmp);
      end;
      if B.Entries = 0 then
         Free (B.Lines);
         Free (B.Labels);
         Free (B.Targets);
      end if;
   end Read_Contents;

   procedure Load_Contents (V : in out FS.Volume; B : in out Book) is
   begin
      if B.Lines /= null then
         return;
      end if;
      Read_Contents (V, B, B.Nav_Href, Is_Nav => True);
      if B.Entries = 0 then
         Read_Contents (V, B, B.Ncx_Href, Is_Nav => False);
      end if;
      if B.Entries = 0 then
         Contents_From_Spine (B);
      end if;
   end Load_Contents;
end Book_Source;
