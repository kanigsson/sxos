#!/bin/bash
# Bare-metal build using the sibling ada_esp32s3 runtime and HAL (no ESP-IDF).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export ESP32S3_RTS_PROFILE=embedded
export HEAP_SIZE=65536 ENV_STACK_SIZE=65536
exec bash "$HERE/../ada_esp32s3/examples/common/bare/bare_build.sh" "$HERE" "_ada_main"
