# X4 Pro SD card and Books listing

Status: **confirmed on hardware** for SD initialization, FAT32 directory reading,
file reads, and on-screen listing. The portrait orientation correction is also confirmed (see
[display bring-up](x4-pro-display-bringup.md)).

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

`src/core/fat32.adb` is a read-only FAT32 reader, generic over a block-read
procedure (`src/device/card.adb` supplies the SD one). It accepts an MBR FAT32
partition (type 0x0B/0x0C) or a FAT32 boot sector at block zero, walks
directories with VFAT long names (checksum-validated, decoded to UTF-8
including surrogate pairs; 8.3 names with the NT lower-case flags otherwise),
looks paths up case-insensitively, and reads files at any byte offset — whole
blocks go straight into the caller's buffer, one multi-block read per
cluster. Every chain walk is bounded by the cluster count. No GPT, FAT12/16 or
exFAT, and nothing is ever written.

`src/core/card_scan.adb` lists `/Books` (`.epub`/`.txt`, sorted) and the
regular `.ttf` faces in `/Fonts`. The first on-device run read a 380 KB font
in 165 ms at the 20 MHz 1-bit clock.

The parser is tested on the host against a FAT32 image with long UTF-8 names
and a deliberately fragmented file (`preview/obj/fat_check`); every file read
back byte-identical, whole and in odd-sized chunks.

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
`src/x4_display.adb` and confirmed right-side up on the panel. The ROM-flashed bootloader, partition
table and app passed esptool's write verification; the device booted normally.
