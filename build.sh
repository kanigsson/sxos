#!/bin/bash
# Bare-metal build using the sibling ada_esp32s3 runtime and HAL (no ESP-IDF).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export ESP32S3_RTS_PROFILE=embedded
export HEAP_SIZE=65536 ENV_STACK_SIZE=65536
# The Ada heap lives in PSRAM (all 8 MiB, see board.ads): font files and book
# text are allocated there.
export HEAP_PSRAM=1
exec bash "$HERE/../ada_esp32s3/examples/common/bare/bare_build.sh" "$HERE" "_ada_main"
