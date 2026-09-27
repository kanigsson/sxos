# sxos roadmap

What could come next. Nothing here is scheduled; items are grouped by area
and ordered roughly by value within each group. How the reader works today
is in [`design.md`](design.md).

## Reading

- **Titles in the Library.** The Library lists file names (`Shelf.List`).
  Take `dc:title` (and `dc:creator`) from the OPF for EPUBs, and keep the
  file name for TXT. `Opf` already parses the package document.
- **Table of contents, next steps** (`design.md`, "Table of contents";
  works on the device, TXT books untried there): prove `Toc`, `Toc_View` and the changed `Opf` and
  `Xhtml_Text`, then put them back on the `-gnatp` list. Then perhaps: a
  way back to the page before a jump; better fallback labels than
  "Chapter N" (the chapter's first line, which needs every chapter
  loaded); unlinked headings (`<span>` in a nav `<li>`) shown as
  headings; the Home key opening Contents.
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
lines broken between syllables, Hangul in `Text_Metrics`' table, and
fallback faces (`design.md`, "Fallback faces").
In order:

- **Hanja.** The fallback face is the smallest one with Hangul; on the
  test card that is NanumGothic, which has no Hanja (Noto Sans KR has).
  With a Nanum reading face, or a non-Korean one, the Hanja of 무정 are
  missing. Options: prefer a face with Hanja when a book needs them (probe
  U+4E00 too), or a third face in the chain, at 4 MB of PSRAM.
- **Proof.** `Fallback` is new and not proved; `Text_Metrics`,
  `Text_Raster`, `Truetype` and `Page_Layout` changed for Korean.
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

- **Heap exhaustion as a proof obligation.** GNATprove assumes every
  allocator succeeds (no `Storage_Error` checks, no heap model), so proof
  did not see the crash of switching from NanumMyeongjo to Noto Sans KR
  with a book open (fragmented heap; `design.md`, "Fallback faces").
  Route large buffers (fonts, chapters, patterns) through a SPARK
  `Try_Allocate` whose result may be null (a `malloc` that returns null
  rather than raising): every dereference is then a proof obligation, so
  a path that does not handle "does not fit" fails proof. Covers graceful
  failure, not the capacity planning (`Make_Room`).
- **Replay the heap on the host.** `ada_esp32s3`'s TLSF allocator is plain
  Ada: an `alloc_check` beside `book_check` could run it over an 8 MB
  arena and replay the device's allocation sequence (elaboration, faces,
  book, face changes), catching fragmentation failures before flashing.
- **The controller in SPARK.** `main.adb`'s mode logic (Library, Reader,
  menu, Settings, saving) calls contracts it cannot check: the target
  builds without `-gnata`, and `main` is not SPARK. Making the state
  machine SPARK, with the hardware behind wrappers as `Reader` and
  `Font_Loader` are, would prove e.g. `Card_Reader.Where`'s
  `Pre => Is_Open` (a periodic save after `Make_Room` closed the book was
  one such near miss).

## Open questions

- Is 10 fast updates between clean refreshes right for page turns of
  full-page text? It was tuned on the Library only.
