-------------------------------------------------------------------------------
--  Xteink X4 Pro board memory profile.
--  Flash/PSRAM sizes were read from the connected ESP32-S3 (16 MiB / 8 MiB).
--  The starter maps 2 MiB of PSRAM because its framebuffer fits comfortably.
-------------------------------------------------------------------------------
package Board is
   Flash_Size : constant := 16 * 1024 * 1024;
   PSRAM_Size : constant := 2 * 1024 * 1024;
end Board;
