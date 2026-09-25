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
`fat_check` and `preview.sh CARD.img ...` — see "Testing against a card
image" in `CLAUDE.md`. Add a few made-up names with Greek, Cyrillic and
emoji to `Books/` for the long-name and fallback paths.
