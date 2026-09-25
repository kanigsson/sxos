with Interfaces; use Interfaces;

with Bytes;

--  An in-memory NOR flash for testing Store_Log: programming can only clear
--  bits, erasing sets a 4 KB sector to 16#FF#.  A power cut can be armed to
--  hit after a number of operations: that operation is left half done
--  (a random prefix programmed, or a sector of garbage for an erase) and
--  Power_Cut is raised.
--
--  Memory stands for the simulated chip and the power-cut countdown; the
--  body is not SPARK, but the spec says what each operation touches so that
--  flow analysis of Store_Log over it is not told flash is stateless.
package Sim_Flash
  with SPARK_Mode => On, Abstract_State => Memory, Initializes => Memory
is
   Size        : constant := 32 * 1024;
   Sector_Size : constant := 4096;

   Power_Cut : exception;

   procedure Read
     (Addr : Unsigned_32; Data : out Bytes.Byte_Array; Ok : out Boolean)
     with Global => (Input => Memory);
   procedure Program
     (Addr : Unsigned_32; Data : Bytes.Byte_Array; Ok : out Boolean)
     with Global => (In_Out => Memory);
   procedure Erase (Addr : Unsigned_32; Ok : out Boolean)
     with Global => (In_Out => Memory);

   --  Cut the power during the N-th operation from now; 0 disarms.
   procedure Arm (N : Natural)
     with Global => (In_Out => Memory);

   procedure Wipe   --  all erased
     with Global => (In_Out => Memory);

   function Erases (Sector : Natural) return Natural
     with Global => Memory;
   function Programs return Natural
     with Global => Memory;
end Sim_Flash;
