# Working in this repo

Bare-metal Ada e-reader for the Xteink X4 Pro (ESP32-S3, UC8279 800×480 1 bpp
SPI panel, SDMMC card, GT911 touch). No ESP-IDF, no FreeRTOS, no Wi-Fi. The
plan and milestones are in `docs/PLAN.md`; hardware findings in `docs/`.

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

## Hardware gotchas

- GPIO1 is the master peripheral rail — raise it before panel, SD or touch.
- A UC8279 refresh is a full refresh (seconds, with flashing) until M3 lands.
- The SD card is **read-only** by design; persistent state goes to internal
  flash (see `docs/PLAN.md`).
