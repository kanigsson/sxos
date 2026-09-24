#!/bin/bash
# Write this project's bare bootloader + partition table + app to an ESP32-S3.
# WARNING: This replaces the current bootloader/partition layout. The full
# original flash backup is in ~/firmware-backups; see docs before proceeding.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PORT="${1:-/dev/ttyACM0}"
BARE="$HERE/../ada_esp32s3/examples/common/bare"

[ -f "$HERE/app.bin" ] || { echo "[flash] build sxos first (./build.sh)" >&2; exit 1; }
[ -f "$HERE/.noidf/bootloader.bin" ] || { echo "[flash] missing generated bare bootloader" >&2; exit 1; }
[ -f "$BARE/vendor/partition-table.bin" ] || { echo "[flash] missing shared partition table" >&2; exit 1; }

# Prefer the locally available esptool; bare_flash.sh handles exact offsets,
# flash mode/frequency/size, and the bare image's expected layout.
export ESP_USE_ESPTOOL=1
exec bash "$BARE/bare_flash.sh" "$HERE" "$PORT"
