# sxos — bare-metal Ada experiments for the Xteink X4 Pro

This is a new standalone project modeled on `../hangul_epd`, targeting the
Xteink X4 Pro's reported ESP32-S3R8 using the local bare-metal Ada runtime and
HAL. It does not use ESP-IDF or FreeRTOS, and it does **not** enable SPARK or
run SPARK proofs.

## Current state

The device boots into the **Library**: it mounts the FAT32 microSD card, lists
the `.epub`/`.txt` files in `/Books` (sorted, long UTF-8 names), loads a
TrueType face from `/Fonts` into PSRAM and renders the list with it, with a
battery indicator from the CW2017 gauge. Left/Right move the selection, a tap
selects a book; opening one is logged only (the reader is milestone M5). Every
screen change is still a full UC8279 refresh. See [`docs/PLAN.md`](docs/PLAN.md).

The card is never written. `/Fonts` may hold several families: only the
regular faces are offered, and `DejaVuSerif.ttf` is the default when present.
If no font can be loaded, the screen says so in the built-in 5×7 font.

The connected device was identified as an ESP32-S3, revision 0.2, with 16 MiB
flash and 8 MiB PSRAM. After safely ejecting CrossPoint USB Drive mode, it
re-enumerated as a `/dev/ttyACM*` port (Espressif USB JTAG/serial). Read-only esptool
queries confirmed ROM-loader access, Secure Boot disabled, and Flash Encryption
disabled. A full-flash backup kept off-device was validated against a
readback of the live device: bytes outside the CrossPoint app partition match
exactly. See [`docs/x4-pro-hardware-bringup.md`](docs/x4-pro-hardware-bringup.md)
for USB/flash recovery details.

## Build

Needs `alr` (Alire 2.x) on `PATH`, with the sibling `../ada_esp32s3`
checkout next to this one:

```sh
./build.sh
ESP_FLASH_MONITOR=1 timeout -s INT 60 ./flash.sh /dev/ttyACM0   # port is positional
```

`build.sh` selects the embedded runtime profile and calls the shared
`../ada_esp32s3/examples/common/bare/bare_build.sh`. Outputs are ignored by git.
The flash script writes the bare bootloader, the shared partition table, and the
application over the ESP32-S3 ROM loader. This replaces the existing boot path;
see the backup/recovery notes before running it.

## Input & touch

Recovered from the hardware-confirmed FreeInk SDK X4 Pro profile (see
`docs/x4-pro-display-bringup.md` for the display equivalent):

- **Nav buttons** — plain digital, active-low, internal pull-ups, confirmed on
  hardware: Left=GPIO0, Right=GPIO7, Power=GPIO3. Left maps to up/previous,
  Right to down/next. GPIO0 is a boot strap: it is only an input after boot.
- **GT911 touch** — shared I2C0 bus SDA=39/SCL=38 at 400 kHz (with the RTC at
  0x51 and the CW2017 gauge at 0x63), INT=GPIO10, RST=GPIO4, address 0x5D
  (alt strap 0x14). The digitizer sits behind an **active-low** power rail on
  GPIO2 (drive LOW; GPIO1 master rail must be HIGH) and **self-loads its
  config** during the standard reset dance — no register upload needed. Status
  register is 0x814E (bit7 = frame ready, low nibble = contact count), points
  at 0x8150 with 8-byte records and X-lo at byte 0; 0x814E must be cleared
  after each read.
- **Touch orientation** — the digitizer reports portrait coordinates directly
  (X 0–480, Y 0–800). FreeInk’s corner-tap-confirmed swap/flip chain reduces to
  using that raw report unchanged in sxos’s portrait frame. Confirmed on
  hardware together with the 180° portrait raster fix: a tap highlights the
  row under the finger (`[tp] contact at X,Y` is logged for each tap).

## Files

`src/core/` is portable and compiles on the host too (mostly SPARK subset);
`src/device/` needs the HAL.

- `src/device/main.adb` — entry point: Books list UI, selection, input loop.
- `src/device/x4_display.adb` — UC8279/SSD1677 controller; ships a `Mono_Frame`.
- `src/device/x4_touch.adb` — GT911 touch driver (rail power, reset dance, polling).
- `src/device/card.adb` — SDMMC slot power/init and block reads.
- `src/device/gauge.adb` — CW2017 fuel gauge (profile upload) + charge line.
- `src/core/fat32.ads` — read-only FAT32/VFAT over any block reader.
- `src/core/card_scan.ads`, `font_catalog.ads`, `font_loader.ads` — /Books
  and /Fonts scanning, face selection, loading a face into the heap.
- `src/core/mono_frame.ads` — 480×800 portrait 1 bpp frame in panel RAM layout.
- `src/core/truetype*.ads`, `text_raster.ads`, `utf8.ads` — on-device outline
  font engine (copied from `../epd_common`, owned here), thresholded to 1 bpp.
- `src/core/shelf.ads`, `status_bar.ads`, `library_view.ads` — the Library
  screen: sorted book list, battery status bar, paged list layout.
- `src/core/bitmap_text.ads`, `x4_font.ads` — 5×7 fallback font.
- `preview/` — host build of `src/core`: renders screens to PGM from a
  directory or a FAT32 image; `fat_check` tests `Fat32` against an image.
- `board.ads` — 16 MiB flash; all 8 MiB PSRAM mapped.
- `docs/PLAN.md` — e-reader plan and milestones.
- `docs/x4-pro-hardware-bringup.md` — USB, flash, backup, and recovery notes.
- `docs/x4-pro-display-bringup.md` — panel pinout, UC8279 refresh, orientation.
- `docs/x4-pro-storage.md` — verified SD wiring, FAT32 listing, limitations.
- `sxos.gpr`, `alire.toml` — runtime/HAL project configuration.

To restore the saved official full-flash dump after a failed custom image, use
ROM download mode and write the full dump from offset zero (this has not been
tested as a write):

```sh
esptool --chip esp32s3 --port "$PORT" write-flash \
  0x0 "$BACKUPS/xteink-x4-pro-esp32s3-2026-09-23-145826.bin"
```
