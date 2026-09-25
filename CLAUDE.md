# Working in this repo

Bare-metal Ada e-reader for the Xteink X4 Pro (ESP32-S3, UC8279 800×480 1 bpp
SPI panel, SDMMC card, GT911 touch). No ESP-IDF, no FreeRTOS, no Wi-Fi. The
plan, milestones and **current status / next steps** are in `docs/PLAN.md`;
hardware findings in `docs/`; the test card in `docs/test-card.md`.

Only what is not guessable from the tree is recorded here.

## Conventions

- **Git identity:** commits are authored as `Johannes Kanig <kanig@adacore.com>`
  (set in the repo-local config). Keep it that way.
- **No machine-specific paths** in tracked files (home directories, `/tmp`,
  backup locations, device serials). Referring to sibling checkouts such as
  `../ada_esp32s3` is fine.
- **SPARK subset, no proofs.** Data-transforming units (parsers, layout, UI
  state, framebuffer maths) are `SPARK_Mode => On` and must stay in the subset,
  but nobody runs gnatprove here — don't add proof-only scaffolding.
- The text engine (`Truetype`, `Truetype.Raster`, `Glyphs`, `Text_Raster`) is
  a **copy** from `../epd_common`, owned by sxos. Diverge freely; do not
  sync it back.

## Build and flash

Needs `alr` (Alire 2.x) on `PATH` and the sibling `../ada_esp32s3` checkout
(runtime, HAL, and the shared bare build/flash scripts).

```sh
./build.sh                                              # -> app.bin
ESP_FLASH_MONITOR=1 timeout -s INT 60 ./flash.sh /dev/ttyACM0
```

- The port is positional, not `-p`.
- Flashing uses the Ada `esp_flash` host tool (no esptool). Use
  `ESP_FLASH_MONITOR=1`: the console is the native USB Serial/JTAG and a
  monitor attached after the reset misses the boot log. The monitor never
  exits by itself, so always bound it with `timeout`.
- `board.ads` sizes are baked into the generated bootloader; changing
  `PSRAM_Size` rebuilds it. All 8 MB of PSRAM is mapped at `0x3D000000`.
- The flash writes bootloader + partition table + app, replacing whatever was
  on the device. Recovery notes: `docs/x4-pro-hardware-bringup.md`.

## Source layout and the host preview

- `src/core/` must compile natively (no HAL, no `ESP32S3.*`); `src/device/`
  is target-only. `preview/preview.gpr` compiles `src/core` on the host.
- The firmware only compiles units in `main`'s closure, so a core unit that
  `main` does not use yet is only checked by the preview build.
- Render a screen from a directory standing in for the SD card
  (`CARD/Books/*.epub|*.txt`, `CARD/Fonts/*.ttf`):

  ```sh
  preview/preview.sh CARD library out.pgm [SELECTED [BATTERY%]]
  ```

  The PGM is portrait, as the device is held. Check layout and font changes
  there before flashing.
- SPARK **legality** (not proof) check of the core — gnatprove from Alire
  (`alr get gnatprove` / the Alire releases dir) with native GNAT on `PATH`:

  ```sh
  (cd preview && gnatprove -P preview.gpr --mode=check_all -j0)
  ```

  `--mode=check` is only a partial check; use `check_all`.
- Never compile with `-gnatW8`: text is raw UTF-8 in `String`.

## Memory

- **The environment stack is 64 KB and an overflow is silent** (the program
  just hangs). Keep large objects off it: the frame, volume and font catalogue
  are library-level in `App_State`; bigger tables go on the heap.
- **The Ada heap is in PSRAM** (`HEAP_PSRAM=1` in `build.sh`, all 8 MiB):
  `new Bytes.Byte_Array (...)` is how font files and book text get loaded.
  The SD driver reads through the FIFO (no DMA), so reading straight into
  PSRAM buffers is fine.
- Ada is case-insensitive: a local `Ok : Boolean` hides an enumeration
  literal `OK` in the same scope. Name such locals `Read_Ok`, `Walk_Ok`, ...

## Testing against a card image

`preview/obj/fat_check` runs `Fat32` over a FAT32 disk image (list
directories, or read a file back whole and in odd-sized chunks), and
`preview/preview.sh CARD.img library out.pgm` renders through the same
`Fat32`/`Card_Scan`/`Font_Loader` chain the firmware uses. Make an image with
`mkfs.fat -C -F 32 -S 512 -s 8 card.img 65536` and fill it with any FAT tool
(e.g. the `pyfatfs` Python package); create/delete files first to get a
fragmented chain.

## Hardware gotchas

- GPIO1 is the master peripheral rail — raise it before panel, SD or touch.
- A UC8279 refresh is a full refresh (seconds, with flashing) until M3 lands.
- The SD card is **read-only** by design; persistent state goes to internal
  flash (see `docs/PLAN.md`).
- The CW2017 gauge reads 0 % until the X4 Pro battery profile is loaded;
  `Gauge.Initialize` checks and uploads it. It shares I2C0 with the GT911,
  so `X4_Touch.Initialize` (which sets the bus up) must run first.
