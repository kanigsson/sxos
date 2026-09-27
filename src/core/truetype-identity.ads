--  Whether two Fonts are the same face.  A Font refers to its file through
--  an access value, which SPARK does not let its code compare: the answer
--  is modelled as a volatile input (the addresses of every loaded file,
--  changing behind the prover's back), so a caller may only store it in a
--  variable and then test that.
package Truetype.Identity
  with SPARK_Mode => On,
       Abstract_State => (Addresses with External => Async_Writers),
       Initializes    => Addresses
is
   function Same_Face (A, B : Font) return Boolean
     with Volatile_Function,
          Global => Addresses;
end Truetype.Identity;
