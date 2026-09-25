with Inflate;
with Inflate.Raw;

package body Deflate is

   procedure Decode
     (Input  : Bytes.Byte_Array;
      Output : in out Bytes.Byte_Array;
      OK     : out Boolean)
   is
      use type Inflate.Status_Type;
      --  Inflate's arrays are 1-based and of its own type: overlay them.
      In_Data : Inflate.Byte_Array (1 .. Input'Length)
        with Import, Address => Input'Address;
      Out_Data : Inflate.Byte_Array (1 .. Output'Length)
        with Import, Address => Output'Address;
      Consumed, Produced : Natural;
      St : Inflate.Status_Type;
   begin
      Inflate.Raw.Decompress (In_Data, Out_Data, Consumed, Produced, St);
      OK := St = Inflate.OK and then Produced = Output'Length;
   end Decode;

end Deflate;
