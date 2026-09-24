-------------------------------------------------------------------------------
--  Xteink X4 Pro board profile -- VALUES BELOW ARE PROVISIONAL.
--
--  The ESP32-S3R8 SoC family is reported for the X4 Pro, but flash size,
--  display connector GPIOs, and attached e-paper controller must be confirmed
--  on this specific revision before flashing or enabling the panel driver.
-------------------------------------------------------------------------------
package Board is
   Flash_Size : constant := 4 * 1024 * 1024;  --  conservative build-time hint
   PSRAM_Size : constant := 2 * 1024 * 1024;  --  map only what this starter needs
end Board;
