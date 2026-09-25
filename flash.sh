#!/bin/bash
# Write this project's bare bootloader + partition table + app to an ESP32-S3.
# WARNING: This replaces the current bootloader/partition layout. The full
# original flash backup should be kept off-device; see docs before proceeding.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PORT="${1:-/dev/ttyACM0}"
BARE="$HERE/../ada_esp32s3/examples/common/bare"

[ -f "$HERE/app.bin" ] || { echo "[flash] build sxos first (./build.sh)" >&2; exit 1; }
[ -f "$HERE/.noidf/bootloader.bin" ] || { echo "[flash] missing generated bare bootloader" >&2; exit 1; }
[ -f "$BARE/vendor/partition-table.bin" ] || { echo "[flash] missing shared partition table" >&2; exit 1; }

# bare_flash.sh flashes with the Ada esp_flash host tool by default, which
# needs no esptool. ESP_FLASH_MONITOR=1 keeps the port open across the reset and
# streams the console (bound it with `timeout`); ESP_USE_ESPTOOL=1 falls back
# to esptool on PATH.
exec bash "$BARE/bare_flash.sh" "$HERE" "$PORT"
