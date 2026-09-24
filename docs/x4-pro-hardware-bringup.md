# Xteink X4 Pro hardware bring-up notes

Status: USB/ROM-loader verified; sxos has been flashed. Physical screen output still needs the operator's visual confirmation.

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

This confirms the ROM download protocol is reachable and chip/flash identification works. Esptool uploaded and ran its temporary stub in RAM; these queries did not write or erase flash.

A further read-only query:

```sh
/tmp/x4-esptool/bin/esptool --chip esp32s3 --port /dev/ttyACM0 get-security-info
```

reported `Secure Boot: Disabled`, `Flash Encryption: Disabled`, and `SPI_BOOT_CRYPT_CNT: 0`. No eFuses were changed.

## Backup validation and recovery confidence

The operator's `~/firmware-backups` contains:

| File | Size | Identification |
|---|---:|---|
| `xteink-x4-pro-esp32s3-2026-09-23-145826.bin` | 16,777,216 bytes (16 MiB) | Full raw flash dump |
| `crosspoint-1.6.0-x4pro.bin` | 5,341,040 bytes | ESP-IDF application image, not a full-flash backup |
| `xteink-x4-pro-crosspoint-full-2026-09-24.bin` | 16,777,216 bytes | Readback snapshot of the live CrossPoint installation before sxos |

SHA-256 values observed:

- Original full dump: `88d16ead9264b5388db67302bc4f06f30f7022df46b7db8cecac09beb3cabd55`
- CrossPoint app: `d20f91502e779a2ba68d9c2423da1a201d74c55badd47f79f84400a320333167`
- CrossPoint full-flash snapshot: `e5c64a72b5ed9e63eb9e65901165fdf809101f96d3aa4da39d6e2137783b9084`

To check the backup without writing to the device, the full current 16 MiB flash was read to `/tmp/x4-current-flash.bin`. The original dump's partition table parses successfully as a 16 MiB ESP-IDF layout:

- NVS `0x9000` (20 KiB)
- OTA metadata `0xe000` (8 KiB)
- app0 `0x10000` (8064 KiB)
- app1 `0x7f0000` (8064 KiB)
- SPIFFS `0xfd0000` (80 KiB)
- coredump `0xfe4000` (112 KiB)

Comparing the original full dump with the live readback, **every differing byte is inside app0** (`0x10000` through `0x527fff`). All bytes before app0 (including the bootloader and partition table) and all bytes after app0 match exactly. This is consistent with the subsequent CrossPoint app flash replacing app0 while leaving the rest of the original flash intact. It is strong evidence that the supplied backup is a complete, correct dump for this exact device and that the current bootloader/partition layout remains intact.

The ROM download path has been exercised for chip ID, flash ID, security information, and a complete flash read. Secure Boot and Flash Encryption are disabled. This makes a same-device full-flash restore through esptool a credible recovery path, but we have **not** performed a write/restore test; do not describe recovery as mathematically guaranteed. The original backup and its hash should remain preserved outside the reader.

The upstream [FreeInk SDK X4 Pro profile](https://github.com/crosspoint-reader/freeink-sdk/blob/main/libs/hardware/BoardConfig/include/BoardConfig.h) documents the following display wiring as hardware-confirmed: SCLK=GPIO12, MOSI=GPIO11, CS=GPIO13, DC=GPIO18, RESET=GPIO14, BUSY=GPIO6. GPIO1 is asserted as the master peripheral-rail enable. The live sxos probe read `FLG=0x13`, `VER=00 0f 68 00 00`; LUT_VER `0x68` identifies this unit as a **UC8279**, not an SSD1677. This live bus probe supersedes the NVS `screenType=0` hint, which is not authoritative. The current code now uses the UC8279 X4 Pro 800x600-addressed/480-visible init and OTP full-refresh sequence.

The first flash produced no visible update because the HAL's software CS pin is not automatically pulsed by `SPI.Transfer`: callers must explicitly `Select_Device(True/False)`. The initial driver omitted this, leaving CS deasserted for all SPI traffic. That is fixed; each transaction now selects the panel, and UC plane uploads hold CS active across their data stream. The latest flash log reports the UC8279 probe and returns from the hello refresh path. A physical on-glass result has not been observable from the host, so operator confirmation is still needed.

To return from USB Drive mode to the serial interface on this CrossPoint installation:

1. Safely eject the reader's mass-storage disk on the host (currently `/dev/sdb`; identify it again rather than assuming the device name).
2. Wait for USB to disconnect/re-enumerate as `Espressif USB JTAG/serial debug unit` and for `/dev/ttyACM*` to appear.
3. A read-only `esptool ... chip-id` query can verify connectivity. Esptool resets the device when it finishes; it does not flash in this query mode.

## Flash decision

From a **recoverable software-brick** perspective, risk is now substantially lower: the ROM downloader works, flash encryption and secure boot are disabled, and the complete original 16 MiB flash image has been structurally validated and compared with the live flash. A boot failure after a software flash should therefore be recoverable by writing that full image back to offset `0x0` over the same USB Serial/JTAG ROM interface. This restore has not actually been tested, so retain the backup and don't call the chance of failure zero.

The sxos bootloader, partition table, and application have now been written. The build uses the confirmed 16 MiB flash size; the custom bare-metal bootloader replaces the CrossPoint boot path, and the shared bare partition table replaces the stock OTA table. The full CrossPoint readback and original full-flash dump are preserved under `~/firmware-backups` for recovery.

The controller probe and UC8279 full B/W refresh sequence now match the live LUT_VER `0x68` unit. The first flash's missing CS assertion has been corrected and the latest image flashed. Physical display content still needs confirmation; if the glass remains unchanged, continue driver timing/data diagnosis and use the preserved same-device full dump to recover if needed.

The remaining “brick” risk is not zero: an incorrect flash operation, loss of power during erase/write, hardware damage, or an unexpected tool/USB failure could still require recovery work. However, the immutable ROM downloader remains available, Secure Boot/Flash Encryption are disabled, and the full 16 MiB same-device CrossPoint and original firmware dumps are preserved. No code path in sxos or the bare loader burns eFuses or disables USB Serial/JTAG. The flash/restore capability was not intentionally locked by this image. A full-dump restore itself has not been tested, but it is the recovery plan if the custom boot path fails.
