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
- **Kerning.** `Truetype` reads no `kern` table (nor GPOS). The classic
  `kern` table is small and noticeably improves Latin text.
- **Margins and line spacing** as settings. They are fixed ratios in
  `Page_Layout.Make` and `Reader_View` today.

## Display

- **Grayscale (anti-aliased) text** through FreeInk's 4-level UC8279 path
  (external LUTs, inverted planes). The largest visual gain. It costs
  refresh time, and `Truetype.Raster`'s supersampling and stem darkening
  would need re-fitting (`text_raster.ads` notes they were never fitted for
  1 bpp Latin text either).
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
