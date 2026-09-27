package body Truetype.Identity
  with SPARK_Mode => Off
is
   function Same_Face (A, B : Font) return Boolean is (A = B);
end Truetype.Identity;
