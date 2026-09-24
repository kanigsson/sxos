# Xteink X4 Pro USB, flash, and recovery notes

Status: ROM download access verified; sxos has been flashed and the reader remains recoverable over USB.

## Device and USB modes

The reader identified itself in CrossPoint USB Drive mode as:

- USB VID:PID `303a:1001`, product `CrossPoint_X4_Pro`
- USB serial / ESP32 MAC `B81F3FD5EF74` / `b8:1f:3f:d5:ef:74`
- `/dev/sdb`: 14.6 GB USB mass-storage SD card (not mounted or written by this setup)

Safely ejecting the CrossPoint drive (`sudo eject -v /dev/sdb`) handed USB from mass storage to the ESP32-S3 USB Serial/JTAG interface. Linux then exposed `/dev/ttyACM0` as `Espressif USB JTAG/serial debug unit`. Identify the device node again before using commands; it can change.

## Chip, flash, and security identification

Read-only esptool v5.4.0 queries over `/dev/ttyACM0` reported:

- ESP32-S3 (QFN56), revision v0.2, USB Serial/JTAG
- 40 MHz crystal, 8 MB embedded AP_3v3 PSRAM
- 16 MB SPI flash, manufacturer `0x0b`, device `0x4018`
- Secure Boot disabled; Flash Encryption disabled; `SPI_BOOT_CRYPT_CNT=0`

Example queries (esptool installed for this session in `/tmp/x4-esptool`):

```sh
/tmp/x4-esptool/bin/esptool --chip esp32s3 --port /dev/ttyACM0 chip-id
/tmp/x4-esptool/bin/esptool --chip esp32s3 --port /dev/ttyACM0 flash-id
/tmp/x4-esptool/bin/esptool --chip esp32s3 --port /dev/ttyACM0 get-security-info
```

These commands connected to the ESP32-S3 ROM loader; esptool's temporary stub ran in RAM. They did not write flash or eFuses. After each query the chip is reset.

## Preserved and verified backups

`~/firmware-backups` contains:

| File | Size | Purpose |
|---|---:|---|
| `xteink-x4-pro-esp32s3-2026-09-23-145826.bin` | 16,777,216 bytes | Original full raw flash dump |
| `crosspoint-1.6.0-x4pro.bin` | 5,341,040 bytes | CrossPoint app image only (not a full-flash restore) |
| `xteink-x4-pro-crosspoint-full-2026-09-24.bin` | 16,777,216 bytes | Full readback of CrossPoint before sxos was flashed |

SHA-256:

- Original full dump: `88d16ead9264b5388db67302bc4f06f30f7022df46b7db8cecac09beb3cabd55`
- CrossPoint app: `d20f91502e779a2ba68d9c2423da1a201d74c55badd47f79f84400a320333167`
- CrossPoint full readback: `e5c64a72b5ed9e63eb9e65901165fdf809101f96d3aa4da39d6e2137783b9084`

The original dump parses as a 16 MiB ESP-IDF layout: NVS at `0x9000`, OTA metadata at `0xe000`, app0 at `0x10000` (8064 KiB), app1 at `0x7f0000` (8064 KiB), SPIFFS at `0xfd0000`, and coredump at `0xfe4000`. A full read of the live CrossPoint flash was byte-identical to the original everywhere outside app0; the only differing bytes were in `0x10000..0x527fff`. This is consistent with the later CrossPoint app-only update replacing app0 while leaving the original bootloader, partition table, and other partitions intact.

The current sxos image replaces the bootloader, partition table, and app. The full original and pre-sxos CrossPoint dumps are preserved off-device. Secure Boot/Flash Encryption are disabled, the ROM downloader has been exercised after sxos was flashed, and neither sxos nor the bare bootloader burns eFuses or disables USB Serial/JTAG. A complete restore has **not** been tested, so recovery is credible but not guaranteed.

If recovery is needed, enter CrossPoint USB Drive mode and eject it to return to `/dev/ttyACM*`, then write a full dump from offset zero. Example for the original official dump (destructive; not run):

```sh
/tmp/x4-esptool/bin/esptool --chip esp32s3 --port /dev/ttyACM0 write-flash \
  0x0 "$HOME/firmware-backups/xteink-x4-pro-esp32s3-2026-09-23-145826.bin"
```

Do not use the 5.3 MB CrossPoint app-only image as a substitute for that full restore if the bootloader or partition table has been changed.

## Flashing sxos

The successful test used the shared bare-metal flash flow to write:

- custom bare bootloader at `0x0`
- shared bare partition table at `0x8000`
- `sxos/app.bin` at `0x10000`

The device returned to USB Serial/JTAG afterward. This demonstrates the custom image did not lock the ROM download path. For the exact panel probe and on-screen result, see [`x4-pro-display-bringup.md`](x4-pro-display-bringup.md).
