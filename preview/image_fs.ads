pragma SPARK_Mode (On);
with Fat32;
with Image_Blocks;

--  Fat32 over a host disk image.  A SPARK instance, so gnatprove checks the
--  generic's body.
package Image_FS is new Fat32 (Image_Blocks.Read_Blocks);
