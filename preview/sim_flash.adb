with Ada.Numerics.Discrete_Random;

package body Sim_Flash
  with SPARK_Mode => Off
is
   subtype Byte_Value is Unsigned_8;
   package Random_Bytes is new Ada.Numerics.Discrete_Random (Byte_Value);
   Gen : Random_Bytes.Generator;

   Mem       : Bytes.Byte_Array (0 .. Size - 1) := (others => 16#FF#);
   Countdown : Natural := 0;
   Erase_Count : array (0 .. Size / Sector_Size - 1) of Natural :=
     (others => 0);
   Program_Count : Natural := 0;

   --  True when this operation is the one the power cut hits.
   function Hit return Boolean is
   begin
      if Countdown = 0 then
         return False;
      end if;
      Countdown := Countdown - 1;
      return Countdown = 0;
   end Hit;

   procedure Read
     (Addr : Unsigned_32; Data : out Bytes.Byte_Array; Ok : out Boolean) is
   begin
      for I in Data'Range loop
         Data (I) := Mem (Natural (Addr) + I - Data'First);
      end loop;
      Ok := True;
   end Read;

   procedure Program
     (Addr : Unsigned_32; Data : Bytes.Byte_Array; Ok : out Boolean)
   is
      Cut  : constant Boolean := Hit;
      Last : Integer := Data'Last;
   begin
      pragma Assert (Addr mod 4 = 0 and then Data'Length mod 4 = 0);
      if Cut then
         Last := Data'First - 1
           + Natural (Random_Bytes.Random (Gen)) * Data'Length / 256;
      end if;
      for I in Data'First .. Last loop
         declare
            M : Unsigned_8 renames Mem (Natural (Addr) + I - Data'First);
         begin
            M := M and Data (I);
         end;
      end loop;
      if Cut then
         if Last < Data'Last then
            --  The byte being programmed: some of its bits made it.
            declare
               M : Unsigned_8 renames
                 Mem (Natural (Addr) + Last + 1 - Data'First);
            begin
               M := M and (Data (Last + 1) or Random_Bytes.Random (Gen));
            end;
         end if;
         raise Power_Cut;
      end if;
      Program_Count := Program_Count + 1;
      Ok := True;
   end Program;

   procedure Erase (Addr : Unsigned_32; Ok : out Boolean) is
      First : constant Natural := Natural (Addr);
   begin
      pragma Assert (Addr mod Sector_Size = 0);
      if Hit then
         for I in First .. First + Sector_Size - 1 loop
            Mem (I) := Mem (I) or Random_Bytes.Random (Gen);
         end loop;
         raise Power_Cut;
      end if;
      Mem (First .. First + Sector_Size - 1) := (others => 16#FF#);
      Erase_Count (First / Sector_Size) := Erase_Count (First / Sector_Size) + 1;
      Ok := True;
   end Erase;

   procedure Arm (N : Natural) is
   begin
      Countdown := N;
   end Arm;

   procedure Wipe is
   begin
      Mem := (others => 16#FF#);
      Erase_Count := (others => 0);
      Program_Count := 0;
   end Wipe;

   function Erases (Sector : Natural) return Natural is (Erase_Count (Sector));
   function Programs return Natural is (Program_Count);
begin
   Random_Bytes.Reset (Gen, 1);
end Sim_Flash;
