# sxos design

How the e-reader is built: a minimal, usable e-reader for the Xteink X4 Pro,
bare-metal Ada on the ESP32-S3, no ESP-IDF, no Wi-Fi. What comes next is in
[`ROADMAP.md`](ROADMAP.md).

## Scope

- **Screens:** a *Library* listing `/Books` on the SD card, a *Reader*, and
  *Settings*. The device boots into the Library.
- **Formats:** EPUB and plain TXT, both decoded on the device.
- **Font:** TrueType files from `/Fonts` on the SD card, rasterised on the
  device. Western scripts only (Latin, Greek, Cyrillic); no CJK.
- **Navigation:** open a book from the Library; return from the Reader to the
  Library. The last position per book survives power-off.
- **Settings:** one screen, reachable from both Library and Reader: reading
  face and size; persisted.
- **Hyphenation** with Liang patterns from the card, per-chapter language.
- **Battery indicator** on every screen.
- **Sleep and off** on the power button.

Not supported: Wi-Fi, CJK, bold/italic, TOC navigation, frontlight
control.

## Constraints

- As much Ada as possible. Data-transforming code is written in **SPARK**
  (`SPARK_Mode => On`) and proved free of run-time errors (silver).
- The text engine (`Glyphs`, `Truetype`, `Truetype.Raster`, `Text_Raster`) is
  **copied into sxos** from `../epd_common` and owned here; sxos may diverge.
  The runtime and HAL still come from `../ada_esp32s3`.
- No machine-specific paths in the repo.

## Architecture

```
 Main (device; glue: poll buttons/touch -> screen logic -> redraw, sleep)
   |
   +-- Screens       SPARK  Library_View, Reader_View, Settings_View,
   |                        Sleep_View, Status_Bar; Shelf (book list)
   +-- Reader        Ada    the open book: chapters, page table, position
   +-- Layout        SPARK  Page_Layout (wrap, paginate), Text_Metrics,
   |                        Hyphenation, Language_Guess
   +-- Book sources  SPARK  Plain_Text (TXT) | EPUB: Zip (directory only),
   |                        Opf (spine), Xml_Scan, Xhtml_Text; Deflate over
   |                        Inflate.Raw (vendor/spark-world); Book_Source
   |                        (not SPARK) loads chapters into PSRAM
   +-- FAT32         SPARK  Fat32, Card_Scan: boot sector / dir entries /
   |                        LFN / cluster chains over caller-supplied
   |                        sectors (no I/O inside)
   +-- Text engine   SPARK  Truetype, Truetype.Raster, Text_Raster (copied);
   |                        Glyph_Cache, Font_Catalog, Font_Loader
   +-- Mono_Frame    SPARK  480x800 portrait 1 bpp, rotation, fills
   +-- Store         SPARK  Store_Log (generic over flash ops), Store_Record,
   |                        Reading_Settings
   |
 hardware (plain Ada, src/device)
   X4_Display (UC8279: full, clean, fast refresh), X4_Touch (GT911),
   Card (SDMMC blocks), Gauge (CW2017 @ 0x63, I2C0), Int_Flash, Power
```

**Host preview.** Everything in `src/core` compiles natively. A host harness
reads a directory or FAT image standing in for the SD card (`Books/`,
`Fonts/`) and renders any screen to a PGM. Layout, EPUB and font problems are
fixed there, not by flashing.

### Key decisions

- **Reading position** = `(spine index, byte offset into that chapter's
  extracted text)`; a TXT file is split into ~64 KB sections that act as
  chapters. It survives font-size changes: re-lay out the chapter and land on
  the page containing the offset. Backward page turns use a page-start table
  built by laying out the chapter from its start (measure-only pass), on the
  heap in PSRAM.
- **Memory:** all 8 MB of PSRAM is mapped and holds the Ada heap: the font
  files, the current chapter's text, the page-start table and the glyph cache.
  DRAM keeps the framebuffer and the rasteriser's working buffers.
- **Font:** the regular `*.ttf` faces in `/Fonts` (style variants such as
  `-Bold`/`-Italic` are recognised by name and kept for later emphasis
  support). The face is a setting; the default is `DejaVuSerif.ttf` if
  present, else the first regular face by name. It is read whole into PSRAM
  and handed to `Truetype.Open`. Must be TrueType-flavoured (`glyf`) —
  the parser does not read CFF/`.otf`. A static TTF such as Charis SIL,
  Literata or Noto Serif covers Latin/Greek/Cyrillic. With no usable font,
  error screens fall back to the built-in 5×7 bitmap font.
- **1 bpp rendering:** anti-aliased coverage is thresholded to black/white,
  with size-derived stem darkening.
- **Persistence:** a log-structured store in internal NOR flash, written via
  the ROM SPI-flash routines (details under "Store" below). The SD card stays
  **read-only**. Positions are written a few seconds after the last page turn
  and before sleep, to limit wear.
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
| any | hold Power 1.5 s | off; hold 1 s to turn on into the Library |
| Settings | tap ◀ / ▶, − / + (or Left / Right) | reading face, reading size, with a sample paragraph; Done returns to the caller |

## Components

Each part below was confirmed on the device, unless its heading says
otherwise; the milestone it came from (M3–M8) is kept in the heading for
finding it in the history.

### Grey text (after M8)

Tried on the device briefly (2026-09-26): it works; the page shows a
fuzzy image for a fraction of a second (the black-and-white base, every
inked pixel black) before the grey pass clears it. The difference from
sharp text is slight to the eye. Refresh times not yet measured.


- A setting (Settings, "Reading text": Sharp / Grey; the third word of the
  settings record) draws the book's text anti-aliased. Everything else —
  status bar, footer, menu, Library, Settings' sample — stays black and
  white, and so does a page with the menu over it.
- Drawing: `Glyph_Cache.Draw_Grey` keeps 2 bpp glyphs (coverage below 3 of
  15 white, from 3 light grey, from 7 dark grey, from 12 black; stem
  darkening `Text_Raster.Grey_Gain_For`, lighter than the 1 bpp ramp). It
  sets every inked pixel black in the frame and marks the grey ones in
  `Mono_Frame.Grey_Masks` (`Grey`: light or dark, `Dark`: dark only),
  CrossPoint's overlay scheme. The masks live on the heap (96 KB).
- Refresh (`X4_Display.Show_Grey`), after FreeInk's `Uc8279X4Driver`
  (displayGrayscaleBase, copyGrayscaleLsb/Msb, displayGray): the frame
  goes up as for `Show`; then the two RAM planes are loaded from frame and
  masks so that white, black, light and dark grey get distinct codes, and
  one refresh with stock's anti-aliasing tables (external LUTs, REG=1, the
  `LUT_VER` 0x68 bank) lightens the grey pixels; both planes then get the
  base back. With that bank light and dark grey are the same tone, so the
  glass shows three levels.
- After the first grey refresh, a fast update under a grey page, and the
  screen after a grey one, go through stock's non-flashing transition
  tables ("prebw_mid") instead of the plain DU, as FreeInk does to keep
  the grey edges' charge in check. Clean and Full refreshes are unchanged.
- Still open: the refresh times (a page turn is now two
  refreshes plus four plane writes, ~0.2 s of SPI at 10 MHz), how grey the
  grey is, whether the level thresholds and stem darkening suit it, and
  whether ghosting stays in check over many turns.
- `PREVIEW_GREY=1 preview.sh CARD.img reader ...` renders the grey page
  with four even levels.

### Kerning (after M8)

Confirmed on the device (2026-09-26): text looks good.


- `Truetype` reads pair kerning from the GPOS `kern` feature — pair
  adjustment lookups, formats 1 (glyph pairs) and 2 (class pairs), also
  behind extension lookups — of the `latn` script's default language
  system (else `DFLT`, else every `kern` feature), and falls back to a
  legacy `kern` table (format 0). Only the first glyph's X advance
  adjustment is applied. Of the test card's faces, DejaVu and Liberation
  have both tables; Literata, Noto and Charis only GPOS (Literata: some
  22 000 pairs in the Latin range). Charis kerns nothing there.
- On all nine regular/bold/italic test faces the values match HarfBuzz for
  every pair of the ~340 kerned characters (Liberation spreads its
  same-glyph pairs over advance and offset; the total is the same).
- `Text_Metrics` tables the pairs of visible Basic Latin, U+00A1–U+017F and
  U+2010–U+2027 (341 characters): in font units per face
  (`Truetype.Kerning_Matrix`, 1–2.5 ms on the host for a whole face), in
  whole pixels per size. Other pairs (Greek, Cyrillic) are not kerned in
  the reading text. The table is ~600 KB, so `Reader` keeps it on the heap.
- `Page_Layout` measures with the kerning of adjacent characters and
  `Reader_View` draws with the same values; a space breaks the chain, a
  soft hyphen does not, and a hyphen drawn at a break is kerned against the
  letter before it. `Text_Raster` (the interface text) kerns through
  `Truetype.Kerning` directly, for any script.
- Kerning moves pens by whole pixels, rounded to nearest, as advances
  already are: at 24 px only pairs of 0.5 px or more show (most of
  Literata's classes do not).
- Pagination is some 3–10 % slower on the host.

### Power off (after M8)

Confirmed on the device:

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

### Library paging and sleep (M8)

Sleep and wake confirmed on the device:

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

### Settings (M7)

Confirmed on the device: size and face changes from the
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

### Store (M6)

Confirmed on the device (positions saved, device rebooted, both books
reopened on the saved pages):

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
  (chapter, page-start offset). `Settings_Key` holds the settings.
- `Main` saves the position 4 s after the last page turn and when a book
  is closed; an unchanged position writes nothing. A save takes < 1 ms,
  mounting (16 KB read) under 1 ms, the first-boot format ~100 ms.
- `preview/obj/store_check` runs the store over a simulated NOR flash with
  ~2900 random power cuts (half-programmed records, half-erased sectors);
  it catches a header-first compaction, the one ordering bug that matters.

### Reader and layout (M5)

Confirmed on the device:

- `Page_Layout` sets a chapter's paragraphs: first-line indent (1.5 em),
  a quarter-line gap between paragraphs, baselines about 1.35 em apart.
  Lines may break at spaces, after a hyphen or dash inside a word and
  at soft hyphens; U+00A0 never breaks. Full lines are **justified**
  (`Reader_View.Justify`), unless a space would stretch beyond
  `Max_Stretch` times its width; justification was off until hyphenation
  landed, as ~40 characters a line left large holes.
- **Paragraphs are set as a whole** (Knuth–Plass, simplified; runs on
  the device, but slowly): `Page_Layout` lists a paragraph's breaks, then a dynamic
  program picks the set with the least demerits: badness `100 r³` of
  each line's stretch ratio (not capped as in TeX, which rejects lines
  over its tolerance instead: capped, two hopelessly loose lines cost the
  same and the program chose the shorter one freely) (spaces stretch by `Stretch_Of` = ½ space
  per unit of `r` and may shrink by `Shrink_Of` = ⅓ space), a penalty per
  hyphen, more for two hyphenated lines in a row or a hyphenated
  second-last line, and for a loose line next to a tight one. As in TeX,
  a first try skips the Liang points (patterns from `/Hyphenation`) and is
  kept if no line is worse than badness 100; otherwise the points are
  added. A paragraph with more than `Max_Breaks` (4096) breaks, or with a
  word wider than the column, is set greedily (`Break_Line`). The
  breaks and costs live in a `Page_Layout.Workspace` (~400 KB, on the
  heap, owned by `Reader`).
- A page is fully determined by its start offset: `Page_Lines` sets the
  paragraph the start is in from its beginning and takes the lines from
  the start on (greedily for the rest of the paragraph, should the start
  not be a line start of its set). `Paginate` builds the chapter's
  page-start table (on the heap, up to 16 384 pages) with it, and drawing
  calls it again, so drawing and pagination cannot disagree.
  `Text_Metrics` caches glyph ids and advances for
  Latin/Greek/Cyrillic/punctuation per (face, size).
- `Glyph_Cache` keeps rendered 1 bpp glyphs in PSRAM (256 KB pool, dropped
  on a font change). The Library now draws in 12 ms warm (110 ms before).
- `Reader` (generic over `Fat32`/`Book_Source`, instantiated at library
  level as `Card_Reader`) turns pages across chapters, skips chapters with
  no text, shows a failed chapter as one page with the reason, and reports
  the position as (chapter, page-start offset).
- Input: Right / tap on the right two thirds forward, Left / left third
  back, tap on the top band for the menu (chapter and page, Library
  button); any button or a tap elsewhere closes the menu.
- Measured on the device: a page draws in 14–25 ms, a DU turn refreshes in
  0.60 s, opening Baskerville at its 200 KB chapter (load, inflate,
  convert, paginate 321 pages) takes 0.40 s. On the host the largest
  chapter (283 KB of text, 435 pages) paginated in 1.4 ms greedily (before
  kerning). Setting whole paragraphs costs about 4x greedy on the host
  (Baskerville's 200 KB chapter: 15 ms against 3.6 ms), two thirds of it
  in Liang hyphenation of every word in the second try. On the device it
  is much worse (first run, 26 px Literata, German): reopening Steppenwolf
  at chapter 5 (78 pages) took 2.5 s, and drawing a page 125 ms.
  `preview/obj/reader_check` walks every book forward and back;
  `book_check --layout` re-measures every line as `Draw_Line` does and
  counts lines the next word would have fitted on.

### Book sources (M4)

The rules below apply to any EPUB, not only the test books:

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

### Display refresh (M3)

Ported from the FreeInk SDK's X4 Pro UC8279 driver
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
ghosting. The SPI clock is 10 MHz (each 60 KB plane takes ~50 ms).
FreeInk also has a 4-level grayscale (AA) path with external LUTs and
inverted planes; see the roadmap.

### Other hardware facts

- **Input:** besides Left (GPIO0), Right (GPIO7) and Power (GPIO3), the
  GT911 has a capacitive **Home key** (FreeInk's X4 Pro profile:
  `hasHomeKey`) — a natural Back button (not used yet).
- **Charging:** the charger's STAT line is GPIO21, active high; `Gauge.Read`
  already reports it.
- **Test data:** `docs/test-card.md`.
