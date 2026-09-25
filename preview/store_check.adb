--  Exercise Store_Log over a simulated NOR flash (Sim_Flash):
--
--    store_check
--
--  1. Puts and remounts without failures: the store always matches a model.
--  2. More keys than the table holds: the most recent ones survive.
--  3. Power cuts at random points of Put and Mount: after every remount each
--     key holds either its last committed value or, for the key being
--     written, the new one.
with Ada.Numerics.Discrete_Random;
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line; use Ada.Command_Line;
with Interfaces; use Interfaces;

with Sim_Flash;
with Sim_Store;
with Store_Record;

procedure Store_Check is
   package Store renames Sim_Store;

   subtype Key_Id is Natural range 0 .. 599;
   package Random_Keys is new Ada.Numerics.Discrete_Random (Key_Id);
   KG : Random_Keys.Generator;

   use type Store_Record.Payload;

   type Model_Array is array (Key_Id) of Unsigned_32;   --  0: never written
   Model  : Model_Array := (others => 0);
   Errors : Natural := 0;
   Serial : Unsigned_32 := 0;

   function K (I : Key_Id) return Store_Record.Key is
     (if I = 0 then Store_Record.Settings_Key
      else Store_Record.Book_Key ("book" & I'Image & ".epub", 1000));

   function Pay (V : Unsigned_32) return Store_Record.Payload is
     (V, V xor 16#5555#, 0, 7);

   function Value (I : Key_Id) return Unsigned_32 is
      P     : Store_Record.Payload;
      Found : Boolean;
   begin
      Store.Lookup (K (I), P, Found);
      if not Found then
         return 0;
      elsif P /= Pay (P (1)) then
         Put_Line ("key" & I'Image & ": corrupt payload");
         Errors := Errors + 1;
      end if;
      return P (1);
   end Value;

   procedure Must_Mount is
      Ok : Boolean;
   begin
      Store.Mount (Ok);
      if not Ok then
         Put_Line ("mount failed");
         Errors := Errors + 1;
      end if;
   end Must_Mount;

   procedure Check_Model (Label : String; Keys : Key_Id) is
   begin
      for I in 0 .. Keys loop
         if Value (I) /= Model (I) then
            Put_Line (Label & ": key" & I'Image & " is" & Value (I)'Image
                      & ", expected" & Model (I)'Image);
            Errors := Errors + 1;
            return;
         end if;
      end loop;
   end Check_Model;

   procedure Put_New (I : Key_Id) is
      Ok : Boolean;
   begin
      Serial := Serial + 1;
      Store.Put (K (I), Pay (Serial), Ok);
      Model (I) := Serial;
      if not Ok then
         Put_Line ("put failed");
         Errors := Errors + 1;
      end if;
   end Put_New;

begin
   Random_Keys.Reset (KG, 7);

   --  1. No failures, 100 keys, a remount every 97 puts.
   Sim_Flash.Wipe;
   Must_Mount;
   for N in 1 .. 20_000 loop
      Put_New (Random_Keys.Random (KG) mod 100);
      if N mod 97 = 0 then
         Must_Mount;
         Check_Model ("plain", 99);
      end if;
   end loop;
   Must_Mount;
   Check_Model ("plain", 99);
   Put_Line ("plain: generation" & Store.Generation'Image & "," &
             Sim_Flash.Programs'Image & " programs, erases per sector"
             & Sim_Flash.Erases (0)'Image & Sim_Flash.Erases (4)'Image);

   --  2. 600 keys through a table of 400: the newest 400 must be there.
   Sim_Flash.Wipe;
   Model := (others => 0);
   Must_Mount;
   for I in Key_Id loop
      Put_New (I);
   end loop;
   Must_Mount;
   if Store.Entries /= Store.Max_Entries then
      Put_Line ("evict: " & Store.Entries'Image & " entries");
      Errors := Errors + 1;
   end if;
   if Value (0) /= Model (0) then
      Put_Line ("evict: settings were forgotten");
      Errors := Errors + 1;
   end if;
   for I in Key_Id'Last - Store.Max_Entries + 2 .. Key_Id'Last loop
      if Value (I) /= Model (I) then
         Put_Line ("evict: recent key" & I'Image & " lost");
         Errors := Errors + 1;
         exit;
      end if;
   end loop;

   --  3. Power cuts.
   Sim_Flash.Wipe;
   Model := (others => 0);
   Must_Mount;
   declare
      Cuts : Natural := 0;
      I    : Key_Id;
      Ok   : Boolean;
      V    : Unsigned_32;
   begin
      for N in 1 .. 50_000 loop
         I := Random_Keys.Random (KG) mod 60;
         Serial := Serial + 1;
         if N mod 3 = 0 then
            Sim_Flash.Arm (1 + Random_Keys.Random (KG) mod 6);
         end if;
         begin
            Store.Put (K (I), Pay (Serial), Ok);
            Sim_Flash.Arm (0);
            Model (I) := Serial;
         exception
            when Sim_Flash.Power_Cut =>
               Cuts := Cuts + 1;
               --  Reboot, possibly cut again while mounting.
               loop
                  if Random_Keys.Random (KG) mod 4 = 0 then
                     Sim_Flash.Arm (1 + Random_Keys.Random (KG) mod 3);
                  end if;
                  begin
                     Store.Mount (Ok);
                     Sim_Flash.Arm (0);
                     exit;
                  exception
                     when Sim_Flash.Power_Cut => Cuts := Cuts + 1;
                  end;
               end loop;
               V := Value (I);
               if V = Serial then
                  Model (I) := Serial;
               elsif V /= Model (I) then
                  Put_Line ("cut: key" & I'Image & " is" & V'Image
                            & ", neither" & Model (I)'Image & " nor"
                            & Serial'Image);
                  Errors := Errors + 1;
               end if;
               Check_Model ("cut", 59);
         end;
         exit when Errors > 5;
      end loop;
      Put_Line ("cuts:" & Cuts'Image & ", generation" & Store.Generation'Image);
   end;

   Put_Line (if Errors = 0 then "all good" else Errors'Image & " failures");
   if Errors > 0 then
      Set_Exit_Status (Failure);
   end if;
end Store_Check;
