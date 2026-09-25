# sxos — a bare-metal Ada e-reader for the Xteink X4 Pro

A minimal e-reader firmware for the Xteink X4 Pro (ESP32-S3R8, 800×480 1 bpp
UC8279 panel, microSD, GT911 touch), written in Ada on a bare-metal runtime:
no ESP-IDF, no FreeRTOS, no Wi-Fi. Data-transforming code (parsers, layout,
UI state, framebuffer maths) is written in the SPARK subset; no proofs are
run.

## Features

- **Library** of the `.epub` and `.txt` files in `/Books` on the SD card:
  sorted, paged, long UTF-8 names.
- **Reader** for EPUB and plain text, both decoded on the device (ZIP,
  Inflate, OPF spine, XHTML to text), laid out chapter by chapter with
  TrueType fonts rasterised on the device. Fast partial refresh for page
  turns, with a clean refresh every few turns.
- **Hyphenation** with Liang's algorithm and hyph-utf8 patterns from the
  card. The language is guessed per chapter, falling back to the EPUB's
  `<dc:language>`.
- **Settings** for the reading face and size, reachable from both screens.
- **Persistence:** the reading position of each book and the settings are
  kept in a log-structured store in internal flash. The SD card is never
  written.
- **Battery indicator** from the CW2017 fuel gauge on every screen.
- **Sleep:** the power button, or 10 minutes without input, puts the device
  into deep sleep; the power button wakes it back into the open book.

Western scripts only (Latin, Greek, Cyrillic); no CJK, no bold/italic, no
table of contents yet. See [`docs/PLAN.md`](docs/PLAN.md) for the design and
the candidates for what comes next.

## The SD card

A FAT32 card with:

- `/Books` — `*.epub` and `*.txt` files. Encrypted (DRM) and ZIP64 EPUBs are
  not supported.
- `/Fonts` — TrueType (`glyf`) fonts, e.g. DejaVu Serif, Noto Serif,
  Literata or Charis SIL. Only regular faces are offered; `DejaVuSerif.ttf`
  is the default when present. CFF-flavoured `.otf` files are not read.
  Without a usable font, the device shows an error in a built-in 5×7 font.
- `/Hyphenation` (optional) — hyph-utf8 pattern files under their usual
  names (`hyph-en-us.pat.txt`, `hyph-de-1996.pat.txt`, ...).

## Controls

| Where | Input | Action |
|---|---|---|
| Library | Left / Right | move the selection |
| Library | tap a row | open the book |
| Library | tap ◀ / ▶ or Settings in the footer | page the list / open Settings |
| Reader | Right, or tap the right two thirds | next page |
| Reader | Left, or tap the left third | previous page |
| any | tap the top band | menu: Library · Settings · battery / progress |
| any | Power | sleep; Power again wakes |

## Building and flashing

You need:

- [Alire](https://alire.ada.dev) 2.x (`alr`) on `PATH`.
- A checkout of [ada_esp32s3](https://github.com/kanigsson/ada_esp32s3) next
  to this one (`../ada_esp32s3`). It provides the runtime, the HAL, the
  build and flash scripts, and pins the GNAT 16.1.0 toolchain, which is
  required.
- The `vendor/spark-world` submodule, which provides Inflate:
  `git submodule update --init`.

```sh
./build.sh                                                  # -> app.bin
ESP_FLASH_MONITOR=1 timeout -s INT 60 ./flash.sh /dev/ttyACM0   # port is positional
```

Flashing uses the Ada `esp_flash` host tool from `ada_esp32s3`; esptool is
not needed. **Flashing replaces the stock bootloader, partition table and
firmware.** Back up the whole flash first. See
[`docs/x4-pro-hardware-bringup.md`](docs/x4-pro-hardware-bringup.md) for
the backup and recovery steps.

## Host preview

`src/core/` also compiles natively. `preview/` renders any screen to a PGM
image from a directory or a FAT32 image standing in for the SD card, and
has host checks for FAT32, the book decoders, the Reader's navigation and
the store:

```sh
preview/preview.sh CARD library out.pgm
preview/preview.sh CARD.img reader out.pgm BOOK
```

See [`CLAUDE.md`](CLAUDE.md) for the details.

## Layout

- `src/core/` — portable code: FAT32, ZIP/OPF/XHTML/TXT book sources, the
  TrueType engine, page layout, hyphenation, the Library, Reader, Settings
  and sleep screens, the 1 bpp frame, and the store's record format.
- `src/device/` — hardware: `x4_display` (UC8279), `x4_touch` (GT911),
  `card` (SDMMC), `gauge` (CW2017), `int_flash` and `device_store`
  (internal flash), `power` (buttons, deep sleep), and `main`.
- `preview/` — host build and checks.
- `vendor/` — the Inflate build from `spark-world`.
- `docs/` — the plan and the hardware findings (display, storage, USB and
  flash recovery).

## Acknowledgements

The display, touch and gauge settings for the X4 Pro follow the
hardware-confirmed profile in the [FreeInk SDK](https://github.com/Free-Ink/freeink-sdk)
(MIT). The CW2017 battery profile in `src/device/gauge.adb` is taken from
it. The deep-sleep sequence follows the stock firmware and
[CrossPoint Reader](https://github.com/crosspoint-reader/crosspoint-reader)
(MIT).

## License

MIT, see [`LICENSE`](LICENSE).
