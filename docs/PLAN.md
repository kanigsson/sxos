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
- **Settings:** one screen, reachable from both Library and Reader: reading
  face and size; persisted.
- **Battery indicator** on every screen.

Out of scope for now: Wi-Fi, CJK, bold/italic, hyphenation, TOC navigation,
grayscale, frontlight control.

## Constraints

- As much Ada as possible. Data-transforming code is written in **SPARK**
  (`SPARK_Mode => On`) and proved free of run-time errors (silver).
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
   +-- Book sources  SPARK  Plain_Text (TXT) | EPUB: Zip (directory only),
   |                        Opf (spine), Xhtml_Text (paragraph text);
   |                        Inflate.Raw from vendor/spark-world; Book_Source
   |                        (not SPARK) loads chapters into PSRAM
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
- **Font:** the regular `*.ttf` faces in `/Fonts` (style variants such as
  `-Bold`/`-Italic` are recognised by name and kept for later emphasis
  support). The face is a setting; the default is `DejaVuSerif.ttf` if
  present, else the first regular face by name. It is read whole into PSRAM
  and handed to `Truetype.Open`. Must be TrueType-flavoured (`glyf`) —
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
| Library | tap Settings (footer) | Settings |
| Library | tap ◀ / ▶ (footer) | previous / next page of books |
| any | Power, or 10 min without input | sleep screen, deep sleep; Power wakes into the open book |
| Settings | tap ◀ / ▶, − / + (or Left / Right) | reading face, reading size, with a sample paragraph; Done returns to the caller |

## Milestones

| # | Milestone | Main risk |
|---|---|---|
| M0 ✓ | Verify the rotation and touch-mapping fixes on the device; commit that work; remove machine-specific paths; add `CLAUDE.md`; map 8 MB PSRAM | — |
| M1 ✓ | Copy the text engine; `Mono_Frame` (1 bpp portrait); host preview harness | text engine decoupled from `Canvas`/`Frame_Buffer` |
| M2 ✓ | FAT32 split into pure parser + `Card`; open/read files; load TTF from `/Fonts`; Library rendered in TrueType; `Gauge` + status bar | SD read throughput for a ~1 MB font |
| M3 ✓ | **UC8279 fast/partial refresh** for page turns; full refresh every N turns | **highest — register/waveform sequence must be taken from FreeInk/CrossPoint and confirmed on the device** |
| M4 ✓ | Book sources: TXT stream; EPUB via ZIP directory + Inflate + OPF spine + XHTML → text | Inflate is the largest new component |
| M5 ✓ | Reader: pagination, page turns, overlay, back to Library | layout speed on long chapters |
| M6 ✓ | `Store`: positions and settings in internal flash | ROM flash calls from the bare runtime (cache/interrupt handling) |
| M7 ✓ | Settings screen (font face and size), shared by both screens | — |
| M8 ✓ | Polish: sorted and paged Library, power button → deep sleep, idle sleep | wake sources on this board |

M3 is independent and can be done whenever the device is at hand. M1, M2 (the
parser part), M4 and M5 can mostly be developed against the host preview.

## Status and next steps

M0–M8 are done and confirmed on the device (see the table): the device boots
into the Library, rendered with DejaVu Serif from the card, with a working
battery gauge; the user found the Library's type size good. Books open
into the Reader and page through on the device, and each book reopens
where it was left, across power cycles. The reading face and size are
set on a Settings screen, and the power button (or 10 minutes idle) puts
it to sleep and wakes it back into the open book; holding it turns the
reader off (see "Power off" below).

**Next:** nothing planned beyond M8. Candidates, roughly by value: the GT911
Home key as Back; a lower-current deep sleep (see below); grayscale (AA)
text through FreeInk's 4-level path; TOC navigation; bold/italic.

**Power off** (after M8), confirmed on the device:

- Holding Power for 1.5 s (`Power_Off_Hold` in `Main`) saves the position
  and settings, draws the off screen (`Sleep_View.Draw` with `Off`) and
  deep-sleeps as for sleep, with an off mark in RTC slow memory (word 3)
  and no book to resume. A short press now acts on release, so the two
  can be told apart.
- The X4 Pro has no power latch: the chip cannot cut its own supply, and
  CrossPoint's "off" is also a deep sleep ("Press and hold power button to
  turn back on"). So any press wakes the chip; `Power.Initialize` sees the
  off mark and, with the pads still held and the panel untouched, requires
  the button to stay down for `Power_On_Hold` (1 s from the start of
  `Initialize`), or goes straight back to sleep. Turning on is a fresh
  start into the Library.
- Off draws the same current as sleep. Dropping the peripheral rail
  (GPIO1) while off would be the next step, but CrossPoint holds it high
  and what else it feeds is unknown; untried.

**M8 (polish)**, sleep and wake confirmed on the device:

- **Library:** already sorted (case-insensitive) and paged; the footer now
  has ◀ / ▶ page arrows either side of the page number
  (`Library_View.Page_Step_At` / `Page_Target`).
- **Deep sleep** (`Power`, device): the power button (GPIO3, active-low,
  debounced; at boot its state starts as "pressed" if still held from the
  wake) or 10 minutes without input (`Idle_Limit`) saves the position (and
  unsaved settings), draws `Sleep_View` with a clean refresh, sends the
  UC8279 POF + DSLP (`X4_Display.Sleep`), and sleeps with RTC EXT1 wake on
  GPIO3 low. It waits for the button's release first, or the low level
  would wake it at once. Pads held through the sleep, as CrossPoint does:
  GPIO1 rail HIGH, GPIO2 (touch) and GPIO5 (SD) enables HIGH = off, panel
  RESET (14) HIGH, frontlight (8, 9) LOW. `Power.Initialize` releases the
  holds and takes GPIO3 back from the RTC mux first thing on every boot.
- **Wake** is a reset. The open book's key is kept in RTC slow memory
  (words 0–2: a mark, then the key), which survives deep sleep but not a
  power cut; after a GPIO wake Main reopens that book at its saved
  position. Asleep in the Library, it wakes to the Library.
- The USB console drops during sleep and re-enumerates after the wake,
  too late for the boot log.
- **Open:** the HAL's `Enter_Deep_Sleep` is a functional deep sleep with
  no regulator (dbias) tuning, so the sleep current is probably above
  what the chip can do; not measured.

**M7 (Settings)**, confirmed on the device: size and face changes from the
Library and from an open book (re-laid out at its passage in 72 ms), and
the settings survive a reboot.

- `Settings_View`: face (◀ / ▶ through the regular faces in `/Fonts`),
  size (− / +, 16–48 px in 2 px steps, default 24), a sample paragraph with
  accents, Greek and Cyrillic (so a face's gaps show), and Done. Left /
  Right change the size. Reached from the Library's footer button and the
  Reader menu's Settings button.
- **Two faces:** the interface (Library, status bars, menu, page numbers)
  stays in the default face at fixed sizes; only the book's text uses the
  reading face. `Glyph_Cache` keys entries by face and holds two faces; a
  third drops everything. Replacing the reading face frees its buffer
  (`Font_Loader.Free`) after `Glyph_Cache.Drop`, since a new face may land
  at the same address.
- `Reading_Settings` stores (size, face hash) under
  `Store_Record.Settings_Key`, only when changed on Done. The face is an
  FNV-1a of its case-folded file name; a face no longer on the card falls
  back to the default.
- Done with a changed face or size re-opens the book at `Reader.Where`
  (clean refresh); otherwise it just redraws.

**M6 (Store)**, confirmed on the device (positions saved, device rebooted,
both books reopened on the saved pages):

- `Int_Flash` (device) reads, programs and erases the internal flash
  through the mask-ROM driver (`esp_rom_spiflash_*`). Each operation runs in
  one IRAM routine: interrupts masked on core 0, **core 1 stalled in
  hardware** (RTC_CNTL SW_STALL_APPCPU, as ESP-IDF does on restart; core 1
  idles in the runtime's scheduler, whose code runs from flash), both
  caches suspended (then waiting for the cache FSMs to go idle, as IDF's ROM
  patches do). PSRAM is unreachable in that window too, so data goes through
  a 1 KB bounce buffer in DRAM. The routine is checked by disassembly: its
  literal pool is in IRAM and every call goes to ROM.
- The ROM driver's chip size is 2 MB (the bare bootloader never sets it),
  so the store lives below that: **32 KB at `0x110000`**, right after the
  1 MB app slot. `Int_Flash` refuses anything below `0x110000` or above
  2 MB.
- `Store_Log` (SPARK, generic over read/program/erase) keeps 32-byte
  CRC-checked records (`Store_Record`) in two 16 KB blocks: append to the
  active one; when full, write the live set to the other block and program
  its header (generation + 1) last. A torn record fails its CRC and is
  skipped. The live set is also a RAM table of 400 entries, least recently
  written position forgotten first (settings never).
- Keys: a book is (FNV-1a of its file name, its size); the payload is
  (chapter, page-start offset). A `Settings_Key` exists for M7.
- `Main` saves the position 4 s after the last page turn and when a book
  is closed; an unchanged position writes nothing. A save takes < 1 ms,
  mounting (16 KB read) under 1 ms, the first-boot format ~100 ms.
- `preview/obj/store_check` runs the store over a simulated NOR flash with
  ~2900 random power cuts (half-programmed records, half-erased sectors);
  it catches a header-first compaction, the one ordering bug that matters.

**M5 (Reader)**, confirmed on the device:

- `Page_Layout` sets a chapter's paragraphs: first-line indent (1.5 em),
  a quarter-line gap between paragraphs, baselines about 1.35 em apart.
  Lines break greedily at spaces and after a hyphen or dash inside a word;
  U+00A0 never breaks. **Ragged right**: justification is implemented
  (`Reader_View.Justify`) but off, because without hyphenation ~40
  characters a line leave large holes, in German especially.
- A page is fully determined by its start offset. `Paginate` builds the
  chapter's page-start table (on the heap, up to 16 384 pages) by a
  measure-only pass, and drawing re-runs `Page_End` from the start, so
  drawing and pagination cannot disagree. `Text_Metrics` caches glyph ids
  and advances for Latin/Greek/Cyrillic/punctuation per (face, size).
- `Glyph_Cache` keeps rendered 1 bpp glyphs in PSRAM (256 KB pool, dropped
  on a font change). The Library now draws in 12 ms warm (110 ms before).
- `Reader` (generic over `Fat32`/`Book_Source`, instantiated at library
  level as `Card_Reader`) turns pages across chapters, skips chapters with
  no text, shows a failed chapter as one page with the reason, and reports
  the position as (chapter, page-start offset). Positions are kept per book
  in RAM until M6.
- Input: Right / tap on the right two thirds forward, Left / left third
  back, tap on the top band for the menu (chapter and page, Library
  button); any button or a tap elsewhere closes the menu.
- Measured on the device: a page draws in 14–25 ms, a DU turn refreshes in
  0.60 s, opening Baskerville at its 200 KB chapter (load, inflate,
  convert, paginate 321 pages) takes 0.40 s. On the host the largest
  chapter (283 KB of text, 435 pages) paginates in 1.4 ms.
  `preview/obj/reader_check` walks every book forward and back.

**M4 (book sources)**, confirmed on the device (opening a book only logs
it for now; the Reader screen is M5). The rules below apply to any EPUB, not
only the test books:

- `Book_Source` (generic over `Fat32`, like `Font_Loader`) opens a book and
  hands out one chapter's text at a time: UTF-8 paragraphs separated by LF.
  `Text (B) (1 .. Text_Last (B))` is valid until the next `Load`.
- **EPUB:** only the ZIP central directory and the OPF stay in PSRAM; each
  chapter is read, inflated (`Inflate.Raw`, from the `vendor/spark-world`
  submodule), CRC-checked and converted on `Load`, so a book's size is
  bounded only by its largest chapter (`Max_Chapter`, 2 MB of XHTML). Spine
  items with no manifest entry or a non-HTML media type are skipped, so
  chapter numbers are spine positions *after* that filtering. No ZIP64 and
  no encryption: a DRM'd book fails with `Bad_Data`. Why sxos has its own
  `Zip` unit instead of `Inflate.ZIP`: `docs/inflate-notes.md`.
- **XHTML → text** (`Xhtml_Text`): block elements and `<br>` end paragraphs,
  empty paragraphs are dropped, white space is collapsed, the XML entities,
  Latin-1 and common typographic entities and numeric references are
  decoded, soft hyphens are dropped, and `head`/`script`/`style`/`svg` are
  skipped. Headings come out as plain paragraphs (no emphasis yet).
- **TXT** (`Plain_Text`): UTF-8, or Windows-1252 when not valid UTF-8; a BOM
  is dropped. Hard-wrapped text (blank lines, and short lines) has single
  line breaks joined; otherwise every line is a paragraph. A single-spaced
  list in hard-wrapped text (e.g. a Gutenberg table of contents) is joined
  into one paragraph. The whole file (up to 3 MB) is normalised at open and
  served as ~64 KB sections cut at paragraph ends, so a long TXT is never
  one huge chapter to lay out. A reading position is (section, offset), the
  same as for EPUB chapters.
- Measured on the device: Musil (1663 chapters, 107 KB directory, 183 KB OPF)
  opens in 0.29 s; the largest test chapter (408 KB XHTML → 283 KB text)
  loads in 0.38 s; typical chapters in 2–90 ms. The heap returns to the same
  free size after each book, so buffers are not leaking. On the host,
  `preview/obj/book_check IMAGE` loads every chapter of every book in an
  image, and its text matched an independent Python extraction.

**M3 (fast refresh)** is ported from the FreeInk SDK's X4 Pro UC8279 driver
(github.com/Free-Ink/freeink-sdk, MIT,
`libs/display/FreeInkDisplay/src/driver/Uc8279X4Driver.cpp`). Measured on
this unit (`LUT_VER=0x68`):

| Refresh | Old plane (DTM1) | Waveform | Time |
|---|---|---|---|
| Full | white | GC (TSSET `0x1E`, CDI `0x97`) | 1.55 s, flashes |
| Clean | inverse of the new frame | GC | 1.51 s, flashes |
| Fast | the frame on the glass | DU (TSSET `0x5A`, CDI `0xD7`) in a full-screen PTIN/PTL window | 0.60 s, no flash |

`X4_Display.Show` does a Fast update by default, a Full one when nothing is
known to be on the glass, and a Clean one after 10 Fast updates in a row
(`Fast_Updates_Per_Clean`). Ten Library selection changes showed no visible
ghosting. Possible later gains: a faster SPI clock (FreeInk uses 16 MHz;
sxos 10 MHz — each 60 KB plane takes ~50 ms), and deferring the DTM1
re-write after a refresh until the next one. FreeInk also has a 4-level
grayscale (AA) path with external LUTs and inverted planes — out of scope
for now, but the natural next display step.

Useful facts for later milestones:

- **Input:** besides Left (GPIO0), Right (GPIO7) and Power (GPIO3), the
  GT911 has a capacitive **Home key** (FreeInk's X4 Pro profile:
  `hasHomeKey`) — a natural Back button (not used yet).
- **Charging:** the charger's STAT line is GPIO21, active high; `Gauge.Read`
  already reports it.
- **Decided:** the font-size setting applies to the reading text only; the
  Library and status bar keep their fixed sizes.
- **Test data:** `docs/test-card.md`.

## Open questions

- Whether 10 fast updates between Clean refreshes is right for page turns of
  full-page text (tuned only on the Library so far).
- Whether the Reader should mark headings (centred, spaced) once there is
  emphasis support; `Xhtml_Text` currently drops that information.
- Whether chapter-crossing turns in very large chapters need the layout
  cached or done incrementally (0.4 s to open a 200 KB chapter is fine so
  far).
