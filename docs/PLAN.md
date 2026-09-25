# sxos e-reader plan

Goal: turn the X4 Pro bring-up into a minimal, usable e-reader — bare-metal
Ada on the ESP32-S3, no ESP-IDF, no Wi-Fi.

## Scope

- **Two screens:** a *Library* listing `/Books` on the SD card, and a
  *Reader*. The device boots into the Library.
- **Formats:** EPUB and plain TXT, both decoded on the device.
- **Font:** a TrueType file from `/Fonts` on the SD card, rasterised on the
  device (as in `hangul_epd`). Western scripts only for now (Latin, Greek,
  Cyrillic); no CJK.
- **Navigation:** open a book from the Library; return from the Reader to the
  Library. The last position per book survives power-off.
- **Settings:** one screen, reachable from both Library and Reader. Font size
  only, for now; persisted.
- **Battery indicator** on every screen.

Out of scope for now: Wi-Fi, CJK, bold/italic, hyphenation, TOC navigation,
grayscale, frontlight control.

## Constraints

- As much Ada as possible. Data-transforming code is written in the **SPARK
  subset** (`SPARK_Mode => On`), but **no proofs are run**.
- The text engine (`Glyphs`, `Truetype`, `Truetype.Raster`, `Text_Raster`) is
  **copied into sxos** from `../epd_common` and owned here; sxos may diverge.
  The runtime and HAL still come from `../ada_esp32s3`.
- No machine-specific paths in the repo.

## Architecture

```
 main (glue: poll input -> UI.Step -> redraw)
   |
   +-- UI            SPARK  (State, Event) -> (State, Redraw); pure
   +-- Layout        SPARK  wrap, paginate, page-start table
   +-- Book sources  SPARK  TXT stream | EPUB: ZIP dir, Inflate, OPF spine,
   |                        XHTML -> paragraph stream (entities, whitespace)
   +-- FAT32         SPARK  boot sector / dir entries / LFN / cluster chains
   |                        over caller-supplied sectors (no I/O inside)
   +-- Text engine   SPARK-ish  Truetype, Raster, Text_Raster (copied)
   +-- Mono_Frame    SPARK  480x800 portrait 1 bpp, rotation, coverage
   |                        threshold, fills, status bar primitives
   +-- State codec   SPARK  saved-state record encode/decode + checksum
   |
 hardware (plain Ada)
   X4_Display (UC8279: full + fast refresh), X4_Touch (GT911), Buttons,
   Card (SDMMC blocks), Gauge (CW2017 @ 0x63, I2C0), Store (internal flash)
```

**Host preview.** Everything marked SPARK compiles natively. A host harness
reads a directory standing in for the SD card (`Books/`, `Fonts/`) and renders
any screen/state to a PGM, like `epub_epd/preview`. Layout, EPUB and font
problems are fixed there, not by flashing.

### Key decisions

- **Reading position** = `(spine index, byte offset into that chapter's
  extracted text)`; TXT is a single "chapter". It survives font-size changes:
  re-lay out the chapter and land on the page containing the offset. Backward
  page turns use a page-start table built by laying out the chapter from its
  start (measure-only pass), cached in PSRAM.
- **Memory:** map all 8 MB of PSRAM (`board.ads` currently maps 2 MB). The
  font file, the current chapter's inflated text and the page-start table live
  there. DRAM keeps the framebuffer(s) and the rasteriser's working buffers.
- **Font:** the first `*.ttf` in `/Fonts` (alphabetical), read whole into
  PSRAM and handed to `Truetype.Open`. Must be TrueType-flavoured (`glyf`) —
  the parser does not read CFF/`.otf`. A static TTF such as Charis SIL,
  Literata or Noto Serif covers Latin/Greek/Cyrillic. With no usable font,
  error screens fall back to the built-in 5×7 bitmap font.
- **1 bpp rendering:** anti-aliased coverage is thresholded to black/white,
  with the existing size-derived stem darkening. At 219 PPI this should read
  well; grayscale is a later option.
- **Persistence:** a dedicated partition in the 16 MB internal NOR flash,
  written via the ROM SPI-flash routines. Log-structured fixed-size records
  (settings; per-book position keyed by file name + size), append until the
  sector is full, then erase and compact into the spare sector. A checksum per
  record; the newest valid record wins. The SD card stays **read-only**.
  Writes happen on page turn only after a short idle delay, and before sleep,
  to limit wear.
- **Battery:** state of charge from the CW2017, shown in a status bar drawn
  on every redraw (no extra refresh just for the battery).

### Interaction

| Where | Input | Action |
|---|---|---|
| Library | Left / Right | move selection |
| Library | tap row | open book |
| Reader | Right, or tap right two thirds | next page |
| Reader | Left, or tap left third | previous page |
| any | tap top band | overlay: Library · Settings · battery / progress |
| Settings | tap − / + | font size, with a sample line; back returns to the caller |

## Milestones

| # | Milestone | Main risk |
|---|---|---|
| M0 ✓ | Verify the rotation and touch-mapping fixes on the device; commit that work; remove machine-specific paths; add `CLAUDE.md`; map 8 MB PSRAM | — |
| M1 | Copy the text engine; `Mono_Frame` (1 bpp portrait); host preview harness | text engine decoupled from `Canvas`/`Frame_Buffer` |
| M2 | FAT32 split into pure parser + `Card`; open/read files; load TTF from `/Fonts`; Library rendered in TrueType; `Gauge` + status bar | SD read throughput for a ~1 MB font |
| M3 | **UC8279 fast/partial refresh** for page turns; full refresh every N turns | **highest — register/waveform sequence must be taken from FreeInk/CrossPoint and confirmed on the device** |
| M4 | Book sources: TXT stream; EPUB via ZIP directory + Inflate + OPF spine + XHTML → text | Inflate is the largest new component |
| M5 | Reader: pagination, page turns, overlay, back to Library | layout speed on long chapters |
| M6 | `Store`: positions and settings in internal flash | ROM flash calls from the bare runtime (cache/interrupt handling) |
| M7 | Settings screen (font size), shared by both screens | — |
| M8 | Polish: sorted and paged Library, power button → deep sleep, idle sleep | wake sources on this board |

M3 is independent and can be done whenever the device is at hand. M1, M2 (the
parser part), M4 and M5 can mostly be developed against the host preview.

## Open questions

- UC8279 fast-refresh sequence and how many fast refreshes can be done before
  ghosting requires a full refresh.
- Which buttons, besides Left (GPIO0), Right (GPIO7) and Power (GPIO3), the
  X4 Pro exposes.
- EPUB edge cases to handle in v1: `<br>`, `<p>`/`<div>`/headings as
  paragraph breaks, `&nbsp;` and numeric entities, images skipped, CSS
  ignored. DRM-protected files show an error.
- Whether a chapter can exceed the PSRAM budget (unlikely, but it must fail
  cleanly).
