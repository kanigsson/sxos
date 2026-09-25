# Xteink X4 Pro display bring-up

Status: **hello and the SD `/Books` listing confirmed visible on the X4 Pro.**
The first portrait listing was upside down; the rotation fix is confirmed on
the panel.

## Live hardware findings

The X4 Pro display connections documented by the hardware-confirmed [FreeInk SDK profile](https://github.com/Free-Ink/freeink-sdk/blob/main/libs/hardware/BoardConfig/include/BoardConfig.h) are:

| Signal | ESP32-S3 GPIO |
|---|---:|
| SPI SCLK | 12 |
| SPI MOSI | 11 |
| EPD CS | 13 |
| EPD D/C | 18 |
| EPD RESET | 14 |
| EPD BUSY | 6 |
| Master peripheral rail | 1, drive HIGH before panel init |

GPIO8/9 drive the warm/cool frontlight, GPIO10 is GT911 touch interrupt, and GPIO7 is a physical navigation button. Do not reuse them for the panel.

The X4 Pro panel controller varies by production batch, so the controller was probed on the live display bus. sxos logged:

```text
[x4] panel probe FLG=0x13 VER=00 0f 68 00 00 BUSY=high
```

For UC81xx parts, VER byte 2 is LUT_VER; `0x68` identifies this unit as a **UC8279**. This live probe is more reliable than the OEM NVS `hw_calib/screenType=0` hint, which looked like the SSD1677 default but did not identify this unit's actual panel. Other X4 Pro units may have SSD1677 or UC8179; the current UC8279 refresh path is selected for this unit's `0x68` result.

## Lessons from the first blank-screen attempt

1. **SPI software CS is not automatic in this HAL.** `Acquire(..., CS_Pin => ...)` sets up a software-CS session but leaves the line deasserted. `Transfer` does not pulse that pin. The first driver omitted `ESP32S3.SPI.Select_Device(Session, True/False)`, so the panel received no selected SPI transactions. Assert CS around every command/data transfer and keep it asserted across a continuous plane upload.
2. **The panel controller matters.** The initial code sent an SSD1677 init/full-update sequence. The live panel is UC8279; the command set, RAM planes, gate offset, and waveform sequence differ. A program reaching its “refresh done” log is not proof the glass received a valid update.
3. **Trust the live probe over a copied configuration hint.** `screenType=0` in NVS was not a reliable indication of this device's live controller. Probe the panel before selecting its driver.
4. **Use the board's real pinout and rail.** GPIO1 must be raised before display initialization. The previously guessed CS/DC/RESET/BUSY values (10/9/8/7) conflicted with touch, frontlight, and button signals.

## UC8279 X4 Pro monochrome refresh used by sxos

The X4 Pro UC8279 addresses 800×600 gates, with the 480 visible rows beginning at gate offset 120. For a B/W full refresh, the driver follows the validated X4 Pro sequence:

- Reset the panel; set PSR `0x37, 0x4D`, TRES `800×600`, GSST `0`, PFS `0x20`, PLL `0x0E`, and gate scan `0x02`.
- Write DTM2 (`0x13`) with 120 white padding rows followed by the 480-row framebuffer.
- Seed DTM1 (`0x10`) white over all 600 addressed rows, so the full OTP waveform starts from white.
- Set CDI `0x97`, CCSET `0x02`, and full-refresh temperature `0x1E`; power on (`0x04`).
- After PON, write PSR `0x17, 0x4D` (REG cleared to select OTP), issue display refresh (`0x12`), and wait for BUSY_N to go low then return high.
- Copy the visible frame to DTM1 as the old-plane baseline.

The panel stays powered after the first PON; later refreshes skip PON, as the stock firmware does.

### Clean and fast (DU) refresh — confirmed on the glass

Both follow the FreeInk SDK `Uc8279X4Driver` (`displayStart` / `startBwRefresh` / `displayFinish`):

- **Clean** is the full GC sequence above with DTM1 seeded with the **inverse** of the new frame instead of white, so every pixel — the white background too — goes through a transition and parked ghost charge is scrubbed.
- **Fast (DU)**: write only DTM2 (DTM1 already holds the shown frame); CDI `0xD7`, CCSET `0x02`, TSSET `0x5A` (selects DU), PFS `0x20`, gate scan `0x02`; PON if needed; **PTIN (`0x91`) and a PTL (`0x90`) window** `x 0..799, gates 120..599, 0x01`; PSR `0x17, 0x4D`; DRF; wait; **PTOUT (`0x92`)**; copy the frame to DTM1. Without the PTL window the DU waveform scans but develops nothing (FreeInk's first field unit).

Measured on this `LUT_VER=0x68` unit, including the 10 MHz SPI plane writes: Full 1.55 s, Clean 1.51 s, Fast 0.60 s with no flashing. Ten fast Library updates in a row left no visible ghosting.

The B/W framebuffer format is 1 bpp, MSB-first, `0xFF` white and zero bits black. The screen driver is `src/device/x4_display.adb`.

## Portrait orientation

The panel RAM is 800×480; the portrait UI uses 480×800 coordinates `(PX, PY)`.
The first Books image used panel coordinates `(799 - PY, PX)` (a 90° rotation),
and the operator confirmed the text was **upside down** even though the directory
listing worked. To rotate that image 180° on the panel, `Draw_Line` now maps
`(PX, PY)` to `(PY, 479 - PX)` instead. This changes only the rasterizer, not
the known-good UC8279 refresh or SD path. The operator confirmed the
corrected text reads right-side up in portrait. See [SD/Books notes](x4-pro-storage.md)
for the card and filesystem findings.

## Verified result

The final bare-metal image was built and flashed through the ESP32-S3 ROM downloader. The monitor showed the UC8279 probe and completed the hello refresh path. The operator then confirmed: **“Yes it shows!! the font is very small but that's fine.”** This is the first confirmed sxos on-glass output.
