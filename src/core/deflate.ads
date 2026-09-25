with Bytes;

--  Raw DEFLATE (RFC 1951) data, as in a ZIP member, decoded by Inflate.Raw.
--
--  The one unit that sees Inflate.Raw: its postcondition refers to
--  proof-only ghost functions, which a unit compiled with -gnata may not
--  name, so the preview compiles this body without it (preview.gpr).
package Deflate is

   --  Decode Input into Output; OK when the data is valid and decodes to
   --  exactly Output'Length bytes.
   procedure Decode
     (Input  : Bytes.Byte_Array;
      Output : in out Bytes.Byte_Array;
      OK     : out Boolean);

end Deflate;
