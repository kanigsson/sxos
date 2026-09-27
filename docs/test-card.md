# The test card

What is on the X4 Pro's microSD card, and how to rebuild the host-side copy
the preview and `fat_check` use. Nothing here is in git: the books are
personal copies and the fonts are third-party.

## On the device's card (FAT32)

- `/Books` — 8 EPUBs: `Baskerville`, `Musil - Der Mann ohne Eigenschaften`
  (2.9 MB, the large-file case), `ai-classics`, `ai-classics2`,
  `hoare1981emperor`, `vbush`, `zauberberg1`, `zauberberg2`.
- `/Fonts` — 18 TrueType files (all OFL / free licences):

  | Family | Files | Source |
  |---|---|---|
  | DejaVu Serif | `DejaVuSerif.ttf` (the default), `-Bold` | Debian `fonts-dejavu` |
  | Liberation Serif | `-Regular`, `-Bold`, `-Italic`, `-BoldItalic` | Debian `fonts-liberation` |
  | Noto Serif | same four, **unhinted** TTFs | `notofonts/latin-greek-cyrillic` release `NotoSerif-v2.015`, `NotoSerif/unhinted/ttf/` |
  | Literata | `Literata12pt-*`, same four | `googlefonts/literata` release `3.002`, `static/ttf/` |
  | Charis SIL | same four | `software.sil.org` `CharisSIL-6.200.zip` — **has no Greek** |

  CrossPoint's own folders (`XTCache`, `XTData`, ...) and Android's are also
  on the card; the reader ignores them.

## Getting files on and off the card

sxos has no USB mass-storage mode. Either put the card in a card reader, or
in an Android reader with USB debugging and use `adb`: the card shows up as
`/storage/XXXX-XXXX` (`adb shell ls /storage`). `adb push` / `adb pull`
work; run `sync` and eject the card on the Android side before moving it.

## Host copy

Make a directory `CARD/` with `Books/` and `Fonts/` holding the same files
(`preview/preview.sh CARD library out.pgm`), and a FAT32 image of it for
`fat_check`, `book_check` and `preview.sh CARD.img ...` — see "Testing
against a card image" in `CLAUDE.md`. Add a few made-up names with Greek,
Cyrillic and emoji to `Books/` for the long-name and fallback paths.

For the TXT paths, add to the image's `/Books`:

- a Project Gutenberg plain text (e.g. `pg3070.txt`, *The Hound of the
  Baskervilles*: CRLF, hard-wrapped, 340 KB, so several sections);
- a Windows-1252 file with German umlauts and a dash, hard-wrapped;
- a UTF-8 file with a BOM, one paragraph per line, with a blank-line scene
  break or two.

The EPUBs cover a single huge chapter (`ai-classics`: 408 KB of XHTML),
many tiny ones (Musil: 1664 spine items, one with no manifest entry, and a
107 KB central directory), and ordinary Gutenberg EPUBs.

## Korean card

A second card for the Korean work (`ROADMAP.md`, "Korean"), kept beside the
checkout rather than in it.

- `/Books` — 8 public-domain Korean stories and novels from
  ko.wikisource.org, exported as EPUB 3 by ws-export.wmcloud.org, with the
  embedded `OPS/fonts/*` (FreeSerif, no Hangul) removed with `zip -d`.
  이광수 - 무정 (10 chapters, one of 133 KB, 450 distinct Hanja) and
  김동인 - 운현궁의 봄 (28 chapters) are the large ones.
- `/Fonts`:

  | Family | Files | Source |
  |---|---|---|
  | NanumMyeongjo, NanumGothic | `-Regular`, `-Bold` | `google/fonts` `ofl/`, unmodified; full Hangul, no Hanja |
  | Noto Sans KR | `-Regular`, `-Bold` | Google Fonts static TTF, subset with `pyftsubset` to Latin, punctuation, symbols, all Hangul and the KS X 1001 Hanja (+ U+3F45 U+6C05 U+7BC8 U+8EFA), no hinting |
  | DejaVu Serif | `DejaVuSerif.ttf` | Debian `fonts-dejavu` |

Build the image as for the main card:
`mkfs.fat -C -F 32 -S 512 -s 8 card.img 65536`, then copy `Books/` and
`Fonts/` with `pyfatfs`.
