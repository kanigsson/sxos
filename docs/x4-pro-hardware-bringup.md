# Xteink X4 Pro hardware bring-up notes

Status: host USB/ROM-loader discovery completed; no firmware was written.

## What was observed

The connected reader identified itself in USB Drive mode as:

- USB VID:PID `303a:1001`
- USB product string `CrossPoint_X4_Pro`
- USB serial `B81F3FD5EF74` (same value as the ESP32 MAC, with punctuation)
- USB mass-storage disk `/dev/sdb`, reported as a 14.6 GB `SD Card`
- No filesystem mount point was present during our check; the block device was not mounted or read/written by this setup session.

The mass-storage interface is CrossPoint's USB Drive mode, not the ESP32 ROM downloader. The operator safely ejected it from the host with `sudo eject -v /dev/sdb` (the agent environment had no sudo authentication). CrossPoint then handed the shared USB connection from mass storage to the ESP32-S3 USB Serial/JTAG peripheral. Linux enumerated `/dev/ttyACM0` as `Espressif USB JTAG/serial debug unit`, still VID:PID `303a:1001`.

This USB Drive-to-Serial/JTAG handoff agrees with the CrossPoint implementation:

- `src/activities/network/UsbDriveActivity.cpp` restarts after the host eject/disconnect.
- `src/platform/UsbSerialJtagHandoff.cpp` returns the shared USB PHY to Serial/JTAG.

## Read-only chip and flash identification

Using esptool v5.4.0 from a temporary virtual environment at `/tmp/x4-esptool`:

```sh
/tmp/x4-esptool/bin/esptool --chip esp32s3 --port /dev/ttyACM0 chip-id
/tmp/x4-esptool/bin/esptool --chip esp32s3 --port /dev/ttyACM0 flash-id
```

Both commands connected successfully. Reported hardware:

- ESP32-S3 (QFN56), revision v0.2
- USB-Serial/JTAG
- 40 MHz crystal
- 8 MB embedded AP_3v3 PSRAM
- 16 MB SPI flash, manufacturer `0x0b`, device `0x4018`
- Flash configuration eFuses report quad I/O and 3.3 V
- MAC `b8:1f:3f:d5:ef:74`

Esptool uploaded and ran its temporary stub flasher in RAM to perform the queries, then reset the chip. No flash contents were written or erased. The device re-enumerated afterward as Espressif USB JTAG/serial at `/dev/ttyACM0`.

This confirms the ROM download protocol is reachable and chip/flash identification works. It does **not** establish that flash writes are permitted under every security configuration; we have not queried secure-boot/flash-encryption state or attempted a write.

## What this means for recovery

The ordinary ESP32-S3 USB recovery path is accessible: esptool was able to connect over the native USB Serial/JTAG interface and run a ROM-loader transaction. That is a strong recovery prerequisite, but it is not a guarantee that every future image can boot or that flash protection is disabled. The original firmware backup was supplied by the operator; its completeness and restore procedure were not independently validated here.

To return from USB Drive mode to the serial interface on this CrossPoint installation:

1. Safely eject the reader's mass-storage disk on the host (currently `/dev/sdb`; identify it again rather than assuming the device name).
2. Wait for USB to disconnect/re-enumerate as `Espressif USB JTAG/serial debug unit` and for `/dev/ttyACM*` to appear.
3. A read-only `esptool ... chip-id` query can verify connectivity. Esptool resets the device when it finishes; it does not flash in this query mode.

## Flash decision: do not flash the current sxos image yet

Although a recovery interface is now confirmed, the current `sxos` binary is **not ready to flash**:

- `src/x4_display.adb` uses provisional, guessed GPIO assignments. The actual X4 Pro display wiring is not confirmed.
- The controller type is unverified. `x4_display.adb` assumes an SSD1677-like controller, 800x480 geometry, 1-bpp RAM format, BUSY polarity, and an incomplete generic init/update sequence.
- `board.ads` and the bare-metal project's bootloader/partition assumptions have not been matched against the live image/layout. The bare build produces a custom bare bootloader; replacing the stock CrossPoint boot path is a larger change than installing an ordinary app binary.
- Flash write protection/security state and the supplied backup's restore process have not been checked.

Wrong panel setup would at best produce a blank/unchanged display; unverified GPIOs may also conflict with board-connected hardware. Replacing bootloader/partition areas with a custom bare-metal image could leave CrossPoint unable to boot until its full flash image is restored. The operator reports that the original firmware is backed up and CrossPoint can be re-downloaded, which improves recovery prospects, but should not substitute for confirming the backup and restore path.

Before any sxos write, establish the panel controller and pin map from this board revision, make the first firmware use a compatible/known flash layout, and verify the full-flash backup/restore procedure. No flashing command has been run by this project setup.
