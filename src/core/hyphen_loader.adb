with Ada.Unchecked_Deallocation;

with Bytes;
with Interfaces;

package body Hyphen_Loader is
   use type Interfaces.Unsigned_32;

   type Trie_Access is access all Hyphenation.Trie;

   procedure Free is new Ada.Unchecked_Deallocation
     (Hyphenation.Trie, Trie_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Bytes.Byte_Array, Bytes.Byte_Array_Access);

   Max_Tag : constant := 35;

   --  The tag asked for last (normalised) and what it gave.
   Loaded_Tag  : String (1 .. Max_Tag);
   Loaded_Last : Natural := 0;
   Asked       : Boolean := False;
   Current     : Trie_Access;

   --  Letters kept before / after a break, as TeX sets them per language.
   procedure Minimums (Primary : String; Left, Right : out Positive) is
   begin
      Left := 2;
      Right :=
        (if Primary = "en" or else Primary = "fr" or else Primary = "pt"
         then 3 else 2);
   end Minimums;

   --  The usual variant for a bare language code.
   function Variant (Primary : String) return String is
     (if Primary = "de" then "de-1996"
      elsif Primary = "en" then "en-us"
      elsif Primary = "el" then "el-monoton"
      elsif Primary = "no" then "nb"
      else "");

   --  Read and build Folder/hyph-<Name>.pat.txt; null if it is not there.
   procedure Load
     (V : in out FS.Volume; Name, Primary : String; T : out Trie_Access)
   is
      F     : FS.File;
      Found : Boolean;
      Data  : Bytes.Byte_Array_Access;
      Count : Natural;
      Ok    : Boolean;
      Left, Right : Positive;
   begin
      T := null;
      if Name = "" then
         return;
      end if;
      FS.Open (V, Folder & "/hyph-" & Name & ".pat.txt", F, Found);
      if not Found or else FS.Is_Directory (F) or else FS.Size (F) = 0 then
         return;
      end if;
      Data := new Bytes.Byte_Array (0 .. Natural (FS.Size (F)) - 1);
      FS.Read (V, F, 0, Data.all, Count, Ok);
      if Ok and then Count = Data'Length then
         declare
            Text : String (1 .. Count)
              with Import, Address => Data (0)'Address;
            Nodes, Pool : Natural;
         begin
            Hyphenation.Measure (Text, Nodes, Pool);
            if Nodes > 0 then
               Minimums (Primary, Left, Right);
               T := new Hyphenation.Trie (Nodes, Pool);
               Hyphenation.Build (Text, Left, Right, T.all, Ok);
               if not Ok then
                  Free (T);
               end if;
            end if;
         end;
      end if;
      Free (Data);
   end Load;

   procedure Select_Language
     (V        : in out FS.Volume;
      Tag      : String;
      Patterns : out Hyphenation.Trie_Ref)
   is
      Norm : String (1 .. Natural'Min (Tag'Length, Max_Tag));
      Dash : Natural := Norm'Last;
   begin
      for I in Norm'Range loop
         declare
            C : constant Character := Tag (Tag'First + I - 1);
         begin
            Norm (I) :=
              (if C in 'A' .. 'Z' then Character'Val (Character'Pos (C) + 32)
               elsif C = '_' then '-'
               else C);
         end;
      end loop;
      for I in reverse Norm'Range loop
         if Norm (I) = '-' then
            Dash := I - 1;
         end if;
      end loop;

      if not (Asked and then Norm = Loaded_Tag (1 .. Loaded_Last)) then
         Free (Current);
         declare
            Primary : constant String := Norm (1 .. Dash);
         begin
            Load (V, Norm, Primary, Current);
            if Current = null and then Primary /= Norm then
               Load (V, Primary, Primary, Current);
            end if;
            if Current = null then
               Load (V, Variant (Primary), Primary, Current);
            end if;
         end;
         Loaded_Tag (1 .. Norm'Length) := Norm;
         Loaded_Last := Norm'Length;
         Asked := True;
      end if;
      Patterns := Hyphenation.Trie_Ref (Current);
   end Select_Language;

   procedure Release is
   begin
      Free (Current);
      Asked := False;
   end Release;

end Hyphen_Loader;
