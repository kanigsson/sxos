# X4 Pro SD card and Books listing

Status: **confirmed on hardware** for SD initialization, FAT32 directory reading, and
on-screen listing. The portrait orientation correction is built but **not yet
flashed/tested** (see [display bring-up](x4-pro-display-bringup.md)).

## Wiring and power

The X4 Pro card is connected to the ESP32-S3's **native SDMMC host**, not
SD-over-SPI: slot 1, 1-bit, CLK=GPIO41, CMD=GPIO42, DAT0=GPIO40. DAT1–3 are
unused. The shared peripheral rail GPIO1 must be driven HIGH first. GPIO5 is
the active-LOW SD gate: pulse HIGH for 80 ms, then hold LOW, waiting 120 ms
before card initialization. The implementation retries initialization *and* a
sector-0 read up to four times. These settings follow the hardware-tested
FreeInk X4 Pro board profile / SDMMC mount sequence; the Ada HAL's
`ESP32S3.SDMMC` handles the native host and 512-byte read-only sector I/O.

Do not use the X4 Pro display's SPI pins for the card. In particular, the
card's SPI-mode pins printed in some board profiles are alternate functions of
the SD slot, not the transport used by the working firmware.

## Filesystem and scope

`src/books_list.adb` is a bounded, read-only FAT32 reader. It accepts either an
MBR FAT32 partition (type 0x0B/0x0C) or a FAT32 boot sector at sector zero,
checks the boot sector and cluster count, walks the root directory to find
`Books` (case-insensitive ASCII), then reads its entries. It follows FAT32
cluster chains, decodes VFAT long names (with short-name checksum validation)
and falls back to 8.3 names. No SD writes are performed. Directories get a `>`
prefix; the first 17 entries in disk order are displayed. Names over 36
characters are shortened with `...`. Non-ASCII UCS-2 characters currently
render as `?`; only ASCII glyphs are included. There is no pagination, sorting,
file opening, GPT, FAT16, or exFAT support. An absent folder, empty folder,
unsupported filesystem, or read error is displayed instead of a listing.

## Observed test

After flashing the first Books image via ESP32-S3 USB Serial/JTAG, the boot log
on the connected device reported:

```text
[x4] panel probe FLG=0x13 VER=00 0f 68 00 00 BUSY=high
[x4] using X4 Pro UC8279 LUT_VER=0x68 waveform
[sxos] SD init: OK
[sxos] Books: OK
[sxos] portrait Books frame submitted; idling
```

The operator confirmed **the directory listing works on the screen**, so the
inserted card has a readable FAT32 `/Books` directory. The text was upside
down in that image. The frame rotation has since been inverted in
`src/x4_display.adb`, but has **not yet been flashed**; the on-screen direction
of the correction remains to be verified. The ROM-flashed bootloader, partition
table and app passed esptool's write verification; the device booted normally.
