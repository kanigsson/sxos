# sxos — bare-metal Ada experiments for the Xteink X4 Pro

This is a new standalone project modeled on `../hangul_epd`, targeting the
Xteink X4 Pro's reported ESP32-S3R8 using the local bare-metal Ada runtime and
HAL. It does not use ESP-IDF or FreeRTOS, and it does **not** enable SPARK or
run SPARK proofs.

## Current state

The first firmware experiment builds an 800×480, 1-bpp framebuffer containing
`hello` and sends it over SPI using the HAL. The panel backend currently assumes
an **SSD1677-compatible** command set. This is only a bring-up starting point:
public X4 Pro reports indicate multiple possible panel controllers, and the
exact X4 GPIO map/controller revision has not yet been verified. The pin values
in `src/x4_display.adb` are provisional example values. **Do not flash this
image or connect the panel driver until the actual unit's pinout and controller
are identified.** The initialization sequence/LUT and pixel polarity may also
need changes.

No Xteink device was visible to this environment during setup. `lsusb` showed
only the root hubs, ASUS Aura LED controller, ASMedia hubs, and wireless device;
there was no Xteink/Espressif USB device and no `/dev/ttyACM*` or `/dev/ttyUSB*`
serial port. The device therefore could not be flashed or tested here. A charge-
only cable, powered-off device, or a device that needs a special boot mode could
explain this; reconnect with a known data cable and check `lsusb`/`dmesg` again.

## Build

The Ada toolchain is installed locally. Add Alire to `PATH` and build:

```sh
export PATH="$HOME/install/alr-2.1.1/bin:$PATH"
./build.sh
```

`build.sh` selects the embedded runtime profile and calls the shared
`../ada_esp32s3/examples/common/bare/bare_build.sh`. Outputs are ignored by git.
No flashing script is provided until device enumeration and board details have
been confirmed.

## Files

- `src/main.adb` — bare-metal entry point and status logging.
- `src/x4_display.adb` — experimental SPI display setup and hello framebuffer.
- `board.ads` — provisional image-header/PSRAM sizing; confirm flash details.
- `sxos.gpr`, `alire.toml` — runtime/HAL project configuration.

## Next hardware steps

1. Connect the X4 Pro with a known data-capable USB cable; check USB enumeration
   and identify whether it exposes ROM download/serial or mass-storage mode.
2. Identify board revision, display controller, and the actual SPI/CS/DC/RESET/
   BUSY GPIO mapping from device firmware/source or board documentation.
3. Confirm flash size and bootloader/partition assumptions before writing any
   image; preserve/recover the stock firmware first.
4. Update the board constants and use the controller-specific power, LUT,
   address-window, and refresh sequence; then validate reset/BUSY on a scope or
   logic analyzer before sending a full frame.
5. Render the `hello` framebuffer and test polarity/rotation on the physical
   panel. The drawing is already separated from panel setup enough to replace
   the experimental controller code without changing the firmware entry point.
