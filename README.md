# sxos — bare-metal Ada experiments for the Xteink X4 Pro

This is a new standalone project modeled on `../hangul_epd`, targeting the
Xteink X4 Pro's reported ESP32-S3R8 using the local bare-metal Ada runtime and
HAL. It does not use ESP-IDF or FreeRTOS, and it does **not** enable SPARK or
run SPARK proofs.

## Current state

The first firmware experiment builds an 800×480, 1-bpp framebuffer containing
`hello` and sends it over SPI using the HAL. The live panel probe reports
UC8279 LUT_VER `0x68`; sxos uses the X4 Pro UC8279 full B/W path. The operator
confirmed that `hello` is visible on the panel; the current 5×7 bitmap glyphs
are small by design. See [`docs/x4-pro-display-bringup.md`](docs/x4-pro-display-bringup.md)
for the pinout, live controller result, UC8279 sequence, and lessons from the
first blank-screen attempt.

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
- `src/x4_display.adb` — experimental SPI display setup and hello framebuffer.
- `board.ads` — detected 16 MiB flash and a 2 MiB PSRAM mapping.
- `docs/x4-pro-hardware-bringup.md` — USB, flash, backup, and recovery notes.
- `docs/x4-pro-display-bringup.md` — verified X4 Pro pinout, UC8279 probe and
  refresh sequence, on-screen result, and bring-up lessons.
- `sxos.gpr`, `alire.toml` — runtime/HAL project configuration.

To restore the saved official full-flash dump after a failed custom image, use
ROM download mode and write the full dump from offset zero (this has not been
tested as a write):

```sh
/tmp/x4-esptool/bin/esptool --chip esp32s3 --port /dev/ttyACM0 write-flash \
  0x0 "$HOME/firmware-backups/xteink-x4-pro-esp32s3-2026-09-23-145826.bin"
```
