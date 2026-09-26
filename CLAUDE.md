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
- **SPARK silver.** Data-transforming units (parsers, layout, UI state,
  framebuffer maths) are `SPARK_Mode => On` and proved free of run-time
  errors at `--level=2`; keep them that way (proof command below). Never
  make a run green by suppressing a check; the only suppressions are four
  flow warnings about deliberately ignored `out` values, each with a
  `Reason`. Not SPARK, by design: `Book_Source`, `Reader`, `Hyphen_Loader`,
  `Font_Loader` (they allocate) and the bodies of `Deflate` and
  `Glyph_Cache` (address overlay, heap pool).
- The preview build has `-gnata`, so contracts and loop invariants run
  there: keep them cheap (no whole-buffer quantifiers in per-byte loops).
- Contracts assume untrusted input: fonts, EPUBs and the FAT volume come
  from the card, so malformed data must be rejected, not asserted away.
- The text engine (`Truetype`, `Truetype.Raster`, `Glyphs`, `Text_Raster`) is
  a **copy** from `../epd_common`, owned by sxos. Diverge freely; do not
  sync it back.
- Inflate is the user's own library, `apps/inflate` (with `libs/ore`) in the
  `vendor/spark-world` submodule (github.com/kanigsson/spark-world), built
  through `vendor/inflate.gpr`. Use it as is: only `Inflate.Raw` (through
  `Deflate`, the one unit that withs it) and `Inflate.CRC32`. Where its
  design does not fit sxos, add to `docs/inflate-notes.md` instead of
  patching it here.
- Avoid functions returning unconstrained `String`s (`Text`, slices through
  expression functions) in per-byte or per-tag loops: each call copies to
  the secondary stack. That made `Xhtml_Text` 3x slower.

## Build and flash

Needs `alr` (Alire 2.x) on `PATH`, the sibling `../ada_esp32s3` checkout
(runtime, HAL, and the shared bare build/flash scripts), and the
`vendor/spark-world` submodule (`git submodule update --init`). Needs GNAT
16 (`gnat_xtensa_esp32_elf` and `gnat_native` 16.1.0): Ore's contracts use
assertion levels, which GNAT 15 rejects. `ada_esp32s3` pins that version.

```sh
./build.sh                                              # -> app.bin
ESP_FLASH_MONITOR=1 timeout -s INT 60 ./flash.sh /dev/ttyACM0
```

- The port is positional, not `-p`.
- The target builds **without `-gnata`**; the host preview keeps it, so
  contracts are checked there. The shared build script does not recompile
  on a switch change alone: after editing switches in `sxos.gpr`, build once
  with `FORCE_BUILD=-f ./build.sh`.
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
  there before flashing. The Reader and Settings need a card image:
  `preview.sh CARD.img reader out.pgm BOOK [CHAPTER [PAGE [SIZE [menu]]]]`,
  `preview.sh CARD.img settings out.pgm [SIZE]`; `PREVIEW_FACE=<file in
  /Fonts>` sets the reading face for both (default: the interface face).
  `preview.sh CARD sleep out.pgm [TITLE]` renders the sleep screen.
- Proof of the core — gnatprove FSF 16.1 from Alire (`alr get gnatprove` /
  the Alire releases dir) with native GNAT 16 on `PATH`:

  ```sh
  (cd preview && gnatprove -P preview.gpr --no-subprojects --level=2 -j16)
  ```

  It must end in "all checks proved" with no warnings. `--no-subprojects`
  leaves Inflate/Ore to spark-world, where they are proved. Generics are
  proved through the SPARK instances in `preview/` (`Image_FS`,
  `Image_Scan`, `Sim_Store`). Avoid `-j0`: on a 32-core host it once left
  gprbuild spinning in phase 2.
- Never compile with `-gnatW8`: text is raw UTF-8 in `String`.

## Memory

- **The environment stack is 64 KB and an overflow is silent** (the program
  just hangs). Keep large objects off it: the frame, volume and font catalogue
  are library-level in `App_State`; bigger tables go on the heap.
- **The Ada heap is in PSRAM** (`HEAP_PSRAM=1` in `build.sh`, all 8 MiB):
  `new Bytes.Byte_Array (...)` is how font files and book text get loaded.
  The SD driver reads through the FIFO (no DMA), so reading straight into
  PSRAM buffers is fine.
- **Never assign an aggregate to a large object** (`X.all := (others =>
  ...)`): GNAT may build it as a temporary on the stack first. Clearing the
  glyph cache's ~80 KB table that way hung the first M5 build. Use a loop.
- Ada is case-insensitive: a local `Ok : Boolean` hides an enumeration
  literal `OK` in the same scope. Name such locals `Read_Ok`, `Walk_Ok`, ...

## Testing against a card image

`preview/obj/fat_check` runs `Fat32` over a FAT32 disk image (list
directories, or read a file back whole and in odd-sized chunks),
`preview/obj/book_check IMAGE [BOOK OUT.txt]` opens every book and loads
every chapter (or dumps one book's text; `--layout [SIZE]` also times
pagination), `preview/obj/reader_check IMAGE [SIZE]` turns through every book
to the end and back and checks the Reader's navigation,
`preview/obj/store_check` runs `Store_Log` through simulated power cuts, and
`preview/preview.sh CARD.img library out.pgm` renders through the same
`Fat32`/`Card_Scan`/`Font_Loader` chain the firmware uses. Make an image with
`mkfs.fat -C -F 32 -S 512 -s 8 card.img 65536` and fill it with any FAT tool
(e.g. the `pyfatfs` Python package); create/delete files first to get a
fragmented chain.

## Hardware gotchas

- GPIO1 is the master peripheral rail — raise it before panel, SD or touch.
- `X4_Display.Show` defaults to a fast (DU, ~0.6 s) update and upgrades it
  itself: to `Full` when nothing is known to be on the glass, to `Clean`
  after `Fast_Updates_Per_Clean` fast updates in a row. Ask for `Full` or
  `Clean` only for a deliberate clean screen (e.g. opening a book).
- The SD card is **read-only** by design; persistent state goes to internal
  flash (see `docs/PLAN.md`).
- **Internal flash writes** (`Int_Flash`): anything that runs while the
  caches are suspended must be in IRAM/DRAM/ROM — no `case` (jump tables
  go to flash `.rodata`), no run-time checks, no PSRAM buffers. Check the
  disassembly of `int_flash__guarded` after touching it. The ROM driver
  thinks the chip is 2 MB; the store is at `0x110000`, and re-flashing does
  not erase it (the flash only covers bootloader, table and app).
- **Deep sleep** holds pads 1, 2, 5, 8, 9 and 14 (RTC hold) and routes
  GPIO3 to the RTC mux; the holds survive the wake reset, so anything that
  drives those pins must come after `Power.Initialize`. Test sleep by
  pressing Power; a monitor misses the wake's boot log.
- The CW2017 gauge reads 0 % until the X4 Pro battery profile is loaded;
  `Gauge.Initialize` checks and uploads it. It shares I2C0 with the GT911,
  so `X4_Touch.Initialize` (which sets the bus up) must run first.
