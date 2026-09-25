#!/bin/bash
# Build the host preview and render one screen.
#   preview/preview.sh CARD_DIR library OUT.pgm [SELECTED [BATTERY%]]
# CARD_DIR stands in for the SD card: CARD_DIR/Books, CARD_DIR/Fonts/*.ttf.
# Uses Alire's native GNAT + gprbuild (override the location with
# ESP32S3_ADA_TOOLCHAINS, as the shared bare scripts do).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TC="${ESP32S3_ADA_TOOLCHAINS:-$HOME/.local/share/alire/toolchains}"
NATGNAT="$(ls -d "$TC"/gnat_native_*/bin | sort -V | tail -1)"
GPRB="$(ls -d "$TC"/gprbuild_*/bin | sort -V | tail -1)"
( cd "$HERE" && PATH="$NATGNAT:$GPRB:$PATH" gprbuild -q -P preview.gpr )
exec "$HERE/obj/preview_main" "$@"
