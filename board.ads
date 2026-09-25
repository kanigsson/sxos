-------------------------------------------------------------------------------
--  Xteink X4 Pro board memory profile.
--  Flash/PSRAM sizes were read from the connected ESP32-S3 (16 MiB / 8 MiB).
--  All 8 MiB of PSRAM is mapped at 0x3D000000: the reader keeps the font file,
--  the current chapter's text and its page table there.
-------------------------------------------------------------------------------
package Board is
   Flash_Size : constant := 16 * 1024 * 1024;
   PSRAM_Size : constant := 8 * 1024 * 1024;
end Board;
