# sxos — bare-metal Ada experiments for the Xteink X4 Pro

This is a new standalone project modeled on `../hangul_epd`, targeting the
Xteink X4 Pro's reported ESP32-S3R8 using the local bare-metal Ada runtime and
HAL. It does not use ESP-IDF or FreeRTOS, and it does **not** enable SPARK or
run SPARK proofs.

## Current state

The initial firmware experiment displayed `hello` on the panel (UC8279
LUT_VER `0x68`). The current firmware powers the SD card, reads the root
`/Books` directory from a **FAT32** card, and displays up to 17 entries in
480×800 portrait orientation (including directories marked `>`). It uses a
scaled ASCII bitmap font; non-ASCII VFAT characters currently show as `?`.
Long names are shortened to 36 characters and later entries are not displayed.
Card/mount errors are shown on the screen and USB serial log; the card is never
written. The reader accepts MBR FAT32 partitions or a FAT32 boot sector at LBA 0
(not GPT/exFAT). The SD initialization, FAT32 `/Books` read, and on-screen
listing were **confirmed on hardware**. The first portrait listing was upside
down; the corrected rotation builds but has **not yet been flashed or verified**.
The SD wiring is X4 Pro SDMMC slot 1, 1-bit (CLK 41, CMD 42, D0 40), with
active-low GPIO5 card power; GPIO1 is the shared peripheral rail. See
[`docs/x4-pro-storage.md`](docs/x4-pro-storage.md) for the card/filesystem
findings and [`docs/x4-pro-display-bringup.md`](docs/x4-pro-display-bringup.md)
for the panel and portrait orientation notes.

The connected device was identified as an ESP32-S3, revision 0.2, with 16 MiB
flash and 8 MiB PSRAM. After safely ejecting CrossPoint USB Drive mode, it
re-enumerated as `/dev/ttyACM0` (Espressif USB JTAG/serial). Read-only esptool
queries confirmed ROM-loader access, Secure Boot disabled, and Flash Encryption
disabled. A full-flash backup in `~/firmware-backups` was validated against a
readback of the live device: bytes outside the CrossPoint app partition match
exactly. See [`docs/x4-pro-hardware-bringup.md`](docs/x4-pro-hardware-bringup.md)
for USB/flash recovery details.

## Build

The Ada toolchain is installed locally. Add Alire to `PATH` and build:

```sh
export PATH="$HOME/install/alr-2.1.1/bin:$PATH"
./build.sh
```

`build.sh` selects the embedded runtime profile and calls the shared
`../ada_esp32s3/examples/common/bare/bare_build.sh`. Outputs are ignored by git.
The flash script writes the bare bootloader, the shared partition table, and the
application over the ESP32-S3 ROM loader. This replaces the existing boot path;
see the backup/recovery notes before running it.

## Files

- `src/main.adb` — bare-metal entry point and status logging.
- `src/x4_display.adb` — SPI display setup and rotated portrait framebuffer.
- `src/books_list.adb` — bounded read-only FAT32/VFAT SD directory scan.
- `src/x4_font.ads` — public-domain 5×7 ASCII bitmap font (from the HAL).
- `board.ads` — detected 16 MiB flash and a 2 MiB PSRAM mapping.
- `docs/x4-pro-hardware-bringup.md` — USB, flash, backup, and recovery notes.
- `docs/x4-pro-display-bringup.md` — panel pinout, UC8279 refresh, orientation.
- `docs/x4-pro-storage.md` — verified SD wiring, FAT32 listing, limitations.
- `sxos.gpr`, `alire.toml` — runtime/HAL project configuration.

To restore the saved official full-flash dump after a failed custom image, use
ROM download mode and write the full dump from offset zero (this has not been
tested as a write):

```sh
/tmp/x4-esptool/bin/esptool --chip esp32s3 --port /dev/ttyACM0 write-flash \
  0x0 "$HOME/firmware-backups/xteink-x4-pro-esp32s3-2026-09-23-145826.bin"
```
