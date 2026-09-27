# sxos roadmap

What could come next. Nothing here is scheduled; items are grouped by area
and ordered roughly by value within each group. How the reader works today
is in [`design.md`](design.md).

## Reading

- **Titles in the Library.** The Library lists file names (`Shelf.List`).
  Take `dc:title` (and `dc:creator`) from the OPF for EPUBs, and keep the
  file name for TXT. `Opf` already parses the package document.
- **Table of contents.** A Reader menu entry that jumps to a chapter, from
  the EPUB's nav document or NCX, falling back to the spine. Navigation is
  page by page only today.
- **Headings.** `Xhtml_Text` flattens headings into plain paragraphs.
  Keeping the fact that a paragraph is a heading would allow centring it
  and adding space around it, with no new fonts.
- **Bold and italic.** Style variants in `/Fonts` are already recognised by
  name. This needs `<em>`/`<strong>` kept through `Xhtml_Text`, and a
  `Glyph_Cache` that holds more than two faces.
- **Progress.** A percentage, or chapter x/y and page n/m, in the status bar
  or the menu, and a progress mark per book in the Library.
- **Kerning beyond Latin.** Only Latin and general punctuation pairs are
  kerned in the reading text (`Text_Metrics`); Greek and Cyrillic would
  need their own table or a larger one. Kerning is also only whole pixels,
  like the advances: fractional pen positions would need layout widths in
  sub-pixel units.
- **Line breaking is too slow on the device** (`design.md`, "Reader and
  layout": 2.5 s to open a chapter, 125 ms to draw a page). Profile
  first; candidates: cache Liang points per word for the chapter
  (a direct-mapped cache hits 15–70 % of hyphenatable words on the test
  books), or find children in the hyphenation trie faster than its
  sibling lists. Then tune: the constants in `Page_Layout` are TeX's,
  scaled; a cost for a very short last line (a lone "son?" after
  "Wat-") and for a hyphen at the end of a page are not there yet.
- **Margins and line spacing** as settings. They are fixed ratios in
  `Page_Layout.Make` and `Reader_View` today.

## Korean

Books and fonts for testing: a Korean card (Wikisource prose, Nanum and
Noto Sans KR faces) rebuilt as in [`test-card.md`](test-card.md). What
already works: file names, EPUB parsing, `Language_Guess` ("ko", no
patterns, so no hyphenation), Hangul drawn with a Korean reading face,
lines broken between syllables, and Hangul in `Text_Metrics`' table.
In order:

- **Glyph fallback.** A code point the face lacks draws nothing and has
  no width: with DejaVu as interface face the Library and the status bar
  show no Hangul, the default reading face shows only punctuation, and
  Nanum drops the Hanja (450 distinct ones in 무정). Take missing glyphs
  from a second face: the reading face when it covers Hangul, else a
  face from `/Fonts` that does. Needs a face per `Text_Metrics` entry and
  a third face in `Glyph_Cache`. Faces are 2–4.3 MB and read whole into
  PSRAM, so avoid loading two large ones.
- **Glyph cache size.** A chapter of 무정 uses 900–1150 distinct
  characters; the cache drops everything past 1536 glyphs or 256 KB.
  Measure on the device, then likely double both.
- **Settings sample.** The sample text is English; show a Korean line
  when the face covers Hangul.
- **Measure on the device:** loading a 3–4 MB face from the card, and
  PSRAM headroom with a large Korean face and a chapter loaded.

## Display

- **Grey text, tuning.** Works on the device (`design.md`, "Grey text"),
  but the gain over sharp text is slight: measure the page turn, tune the level
  thresholds (`Glyph_Cache`) and stem darkening (`Text_Raster.Grey_Gain_For`),
  and watch ghosting over many turns. Then: a true four-tone bank (FreeInk
  builds one by time-scaling the X3's four-grey waveform, for images; it is
  slower), grey for the Settings sample so the setting can be judged there,
  and perhaps the interface text.
- **Faster page turns.** SPI at 16 MHz, as FreeInk uses, instead of 10 MHz
  (`X4_Display`): ~20 ms less per 60 KB plane. Deferring the DTM1 re-write
  after a refresh until the next one.

## Input and power

- **Home key as Back.** The GT911 has a capacitive Home key (FreeInk's X4
  Pro profile: `hasHomeKey`); unused so far.
- **Lower sleep current.** The HAL's `Enter_Deep_Sleep` does no regulator
  (dbias) tuning. Measure the current first.
- **Drop the peripheral rail when off.** GPIO1 is held high through sleep
  and off, as CrossPoint does; what else it feeds is unknown. Untried.

## Robustness and performance

- **Large chapters.** Opening a 200 KB chapter takes 0.4 s (load, inflate,
  convert, paginate). Bigger books may need the layout cached or done
  incrementally, especially for chapter-crossing turns.
- **Subfolders in `/Books`.** `Card_Scan` skips them.
- **Inflate without checks.** Inflate keeps run-time checks on the target
  until spark-world states its proof status (`inflate-notes.md` §7); then
  it can join the `-gnatp` list in `sxos.gpr`.

## Open questions

- Is 10 fast updates between clean refreshes right for page turns of
  full-page text? It was tuned on the Library only.
