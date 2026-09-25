# Using `inflate` in sxos: where its design does not fit

sxos decodes EPUBs with [kanigsson/inflate](https://github.com/kanigsson/inflate)
(git submodule `vendor/inflate`). It uses `Inflate.Raw` and `Inflate.CRC32`.
It does not use `Inflate.ZIP`. This file records where the library's design
did not fit this reader, as input for improving the library. The decoder
itself was correct on every member of the test books, with every CRC
matching.

## 1. `Inflate.ZIP` needs the whole archive in memory

`Open`, `Next` and `Extract` all take `Archive : Byte_Array`, the complete
file. On the X4 Pro a book is read from the SD card, and PSRAM is 8 MB,
shared with the font and the chapter buffers. EPUBs over a few MB (Musil here
is 2.9 MB, and illustrated books are much larger) cannot be loaded whole, and
there is no reason to: a reader needs the central directory once and one
member at a time.

sxos therefore has its own `src/core/zip.ads` (about 150 lines, SPARK), which
parses only the pieces the caller reads:

- `Find_Directory (Tail, File_Size, ...)`: the end record, found from the
  last `22 + 65535` bytes and the file size.
- `Find (Dir, Name, ...)`: a lookup in the central directory bytes alone.
  Offsets stay file-absolute, not relative to a buffer.
- `Data_Offset (Header, ...)`: the member's data offset, computed from its
  30-byte local header.

The member's compressed bytes are then read into their own buffer and handed
to `Inflate.Raw.Decompress`. The CRC is checked with `Inflate.CRC32`.

**Suggestion:** split `Inflate.ZIP` along those lines: end record from a
tail buffer, directory iteration over the directory bytes only,
local-header parsing from its fixed part, and `Extract` from a buffer holding
just the member's compressed data (still checking CRC and size). The current
whole-archive API is easy to rebuild on top of those pieces. An EPUB also
wants lookup by name (exact, falling back to ASCII case-insensitive, because
hrefs and archive names sometimes disagree on case). Iteration is enough for
that, but a `Find` would save every caller writing it.

## 2. A distinct, 1-based `Byte_Array`

`Inflate.Byte_Array` is `array (Buffer_Index range <>)` with
`Buffer_Index` starting at 1. sxos's byte type is
`Bytes.Byte_Array (Natural range <>)`, 0-based. The framebuffer, FAT sectors,
font data and book buffers all use it, and the FAT32 reader fills it.
Converting between the two types needs either a copy or an address overlay:

```ada
Input : Inflate.Byte_Array (1 .. Packed)
  with Import, Address => B.Packed (0)'Address;
```

sxos does the overlay in `Book_Source`, which is not SPARK anyway (it
allocates). A SPARK caller could not do this; it would have to copy each
chapter, which is hundreds of KB here.

**Suggestion:** make the decoder generic over the caller's array type (a
formal `type Index is range <>` and
`type Byte_Array is array (Index range <>) of Unsigned_8`). Alternatively,
accept any index range, including a first index of 0. The "one past the end
never overflows" reason for `Buffer_Index` works just as well with
`Natural range 0 .. Natural'Last - 1`.

## 3. One-shot only: peak memory is compressed + inflated

`Decompress` needs the whole compressed member in memory and a buffer for the
whole result. For the largest test chapter (111 KB compressed, 408 KB of
XHTML), sxos holds 111 KB + 408 KB, plus 283 KB for the extracted text,
all at once. That fits in 8 MB. But a streaming interface would allow:

- reading compressed data from the card in blocks;
- feeding output straight into the XHTML→text converter, dropping the
  408 KB intermediate buffer;
- stopping early, e.g. inflating only as far as the page being opened.

**Suggestion:** a resumable decoder with a 32 KB window, keeping its state
in a record and taking input and output in pieces. This isn't needed by sxos
today, but it is the change that would matter most for larger chapters.

## Measurements (for context, not problems)

Host, the 408 KB chapter from `ai-classics.epub`: `Inflate.Raw` 1.2 ms,
`Inflate.CRC32` 0.6 ms, sxos's XHTML→text conversion 1.0 ms.

On the device, loading that chapter (SD read, inflate, CRC, text) took
877 ms with the whole firmware built with `-gnata`, 773 ms without it, and
382 ms once sxos's own converter was fixed. The library was never the
bottleneck. sxos now builds the target without `-gnata`; the host preview
keeps it.
