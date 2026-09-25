with Ada.Unchecked_Conversion;
with System; use System;
with System.Machine_Code; use System.Machine_Code;
with System.Storage_Elements; use System.Storage_Elements;

package body Int_Flash is

   --  Guarded runs with the cache off: a failed check would call into the
   --  run-time in flash.  The wrappers below check their arguments instead.
   pragma Suppress (All_Checks);

   Chunk : constant := 1024;

   --  In internal RAM (.bss): the ROM reads and writes it with the cache off.
   Bounce : Bytes.Byte_Array (0 .. Chunk - 1) with Alignment => 4;

   Unlocked : Boolean := False with Volatile;

   --  ROM entry points (ESP32-S3 ROM linker script).
   Rom_Suspend_ICache : constant := 16#4000_189C#;
   Rom_Resume_ICache  : constant := 16#4000_18A8#;
   Rom_Suspend_DCache : constant := 16#4000_18B4#;
   Rom_Resume_DCache  : constant := 16#4000_18C0#;
   Rom_Erase_Sector   : constant := 16#4000_09FC#;
   Rom_Write          : constant := 16#4000_0A14#;
   Rom_Read           : constant := 16#4000_0A20#;
   Rom_Unlock         : constant := 16#4000_0A2C#;
   Rom_Legacy_Data    : constant := 16#3FCE_FFE4#;  --  pointer to descriptor

   type Suspend_Fn is access function return Unsigned_32
     with Convention => C;
   type Resume_Fn is access procedure (Autoload : Unsigned_32)
     with Convention => C;
   type Erase_Fn is access function (Sector : Unsigned_32) return Integer
     with Convention => C;
   type Transfer_Fn is access function
     (Flash_Addr : Unsigned_32; Buffer : Address; Len : Integer)
      return Integer
     with Convention => C;
   type Unlock_Fn is access function return Integer
     with Convention => C;

   function To_Suspend is new Ada.Unchecked_Conversion (Address, Suspend_Fn);
   function To_Resume is new Ada.Unchecked_Conversion (Address, Resume_Fn);
   function To_Erase is new Ada.Unchecked_Conversion (Address, Erase_Fn);
   function To_Transfer is new Ada.Unchecked_Conversion (Address, Transfer_Fn);
   function To_Unlock is new Ada.Unchecked_Conversion (Address, Unlock_Fn);

   --  RTC_CNTL: the APP CPU stall fields (C0 in OPTIONS0 bits 1..0, C1 in
   --  SW_CPU_STALL bits 25..20; 2 and 16#21# together stall the core), and
   --  EXTMEM_CACHE_STATE (ICache FSM bits 11..0, DCache 23..12; 1 = idle).
   Options0 : Unsigned_32
     with Import, Volatile, Address => To_Address (16#6000_8000#);
   Stall    : Unsigned_32
     with Import, Volatile, Address => To_Address (16#6000_80BC#);
   Cache_State : Unsigned_32
     with Import, Volatile, Address => To_Address (16#600C_4130#);

   Op_Read  : constant := 0;
   Op_Write : constant := 1;
   Op_Erase : constant := 2;

   --  One ROM operation on Len bytes of Bounce (Read, Write) or on the
   --  sector at Flash_Addr (Erase).  Returns the ROM's result, 0 for OK.
   --  Everything it touches must be in IRAM, DRAM or ROM: no case
   --  statements (jump tables go to .rodata in flash), no run-time calls.
   function Guarded
     (Op : Unsigned_32; Flash_Addr : Unsigned_32; Len : Integer)
      return Integer
     with Linker_Section => ".iram1.sxos_flash";

   function Guarded
     (Op : Unsigned_32; Flash_Addr : Unsigned_32; Len : Integer)
      return Integer
   is
      PS     : Unsigned_32;
      I_Auto : Unsigned_32;
      D_Auto : Unsigned_32;
      Result : Integer := 0;
   begin
      Asm ("rsil %0, 15", Outputs => Unsigned_32'Asm_Output ("=r", PS),
           Volatile => True, Clobber => "memory");

      Options0 := (Options0 and not 16#3#) or 16#2#;
      Stall := (Stall and not 16#03F0_0000#) or 16#0210_0000#;

      I_Auto := To_Suspend (To_Address (Rom_Suspend_ICache)).all;
      while (Cache_State and 16#FFF#) /= 1 loop
         null;
      end loop;
      D_Auto := To_Suspend (To_Address (Rom_Suspend_DCache)).all;
      while (Shift_Right (Cache_State, 12) and 16#FFF#) /= 1 loop
         null;
      end loop;

      if Op /= Op_Read and then not Unlocked then
         Result := To_Unlock (To_Address (Rom_Unlock)).all;
         Unlocked := Result = 0;
      end if;

      if Result = 0 then
         if Op = Op_Read then
            Result := To_Transfer (To_Address (Rom_Read)).all
              (Flash_Addr, Bounce'Address, Len);
         elsif Op = Op_Write then
            Result := To_Transfer (To_Address (Rom_Write)).all
              (Flash_Addr, Bounce'Address, Len);
         else
            Result := To_Erase (To_Address (Rom_Erase_Sector)).all
              (Flash_Addr / Sector_Size);
         end if;
      end if;

      To_Resume (To_Address (Rom_Resume_DCache)).all (D_Auto);
      To_Resume (To_Address (Rom_Resume_ICache)).all (I_Auto);

      Options0 := Options0 and not 16#3#;
      Stall := Stall and not 16#03F0_0000#;

      Asm ("wsr.ps %0" & ASCII.LF & "rsync",
           Inputs => Unsigned_32'Asm_Input ("r", PS),
           Volatile => True, Clobber => "memory");
      return Result;
   end Guarded;

   function In_Range (Addr : Unsigned_32; Len : Natural) return Boolean is
     (Addr >= App_End and then Addr mod 4 = 0 and then Len mod 4 = 0
      and then Unsigned_32 (Len) <= Limit - Addr and then Addr < Limit);

   procedure Read
     (Addr : Unsigned_32; Data : out Bytes.Byte_Array; Ok : out Boolean)
   is
      Done : Natural := 0;
      N    : Natural;
   begin
      Ok := In_Range (Addr, Data'Length);
      while Ok and then Done < Data'Length loop
         N := Natural'Min (Chunk, Data'Length - Done);
         Ok := Guarded (Op_Read, Addr + Unsigned_32 (Done), N) = 0;
         Data (Data'First + Done .. Data'First + Done + N - 1) :=
           Bounce (0 .. N - 1);
         Done := Done + N;
      end loop;
   end Read;

   procedure Program
     (Addr : Unsigned_32; Data : Bytes.Byte_Array; Ok : out Boolean)
   is
      Done : Natural := 0;
      N    : Natural;
   begin
      Ok := In_Range (Addr, Data'Length);
      while Ok and then Done < Data'Length loop
         N := Natural'Min (Chunk, Data'Length - Done);
         Bounce (0 .. N - 1) :=
           Data (Data'First + Done .. Data'First + Done + N - 1);
         Ok := Guarded (Op_Write, Addr + Unsigned_32 (Done), N) = 0;
         Done := Done + N;
      end loop;
   end Program;

   procedure Erase (Addr : Unsigned_32; Ok : out Boolean) is
   begin
      Ok := In_Range (Addr, Sector_Size) and then Addr mod Sector_Size = 0
        and then Guarded (Op_Erase, Addr, 0) = 0;
   end Erase;

   function Rom_Chip_Size return Unsigned_32 is
      Descriptor : Address
        with Import, Address => To_Address (Rom_Legacy_Data);
      --  esp_rom_spiflash_chip_t: device_id, chip_size, ...
      Size : Unsigned_32 with Import, Address => Descriptor + 4;
   begin
      return Size;
   end Rom_Chip_Size;

end Int_Flash;
