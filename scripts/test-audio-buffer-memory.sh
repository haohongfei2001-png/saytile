#!/bin/bash
# Accelerated VoiceSegmenter allocation regression; not a wall-clock audio soak.
set -euo pipefail
cd "$(dirname "$0")/.."
SAYTILE_BUFFER_SCRATCH="${SAYTILE_BUFFER_SCRATCH:-/tmp/saytile-audio-buffer}"
mkdir -p "$SAYTILE_BUFFER_SCRATCH"
swift build --product SaytileKit --scratch-path "$SAYTILE_BUFFER_SCRATCH/build" -Xswiftc -enable-testing >&2
SAYTILE_BUFFER_BIN="$(swift build --product SaytileKit --scratch-path "$SAYTILE_BUFFER_SCRATCH/build" -Xswiftc -enable-testing --show-bin-path)"
SAYTILE_BUFFER_MODULE_MAP="$SAYTILE_BUFFER_BIN/../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap"
if [[ ! -f "$SAYTILE_BUFFER_MODULE_MAP" ]]; then SAYTILE_BUFFER_MODULE_MAP="$SAYTILE_BUFFER_BIN/CAudio.build/module.modulemap"; fi
test -f "$SAYTILE_BUFFER_MODULE_MAP"
swiftc -O -swift-version 6 -parse-as-library -D SAYTILE_PACKAGE_PROBE -I Sources/CSQLite \
  -I "$SAYTILE_BUFFER_BIN" -I "$SAYTILE_BUFFER_BIN/Modules" \
  -Xcc "-fmodule-map-file=$SAYTILE_BUFFER_MODULE_MAP" \
  -L "$SAYTILE_BUFFER_BIN" -lSaytileKit -lc++ \
  tests/fixtures/AudioBufferMemoryProbe.swift -o "$SAYTILE_BUFFER_SCRATCH/buffer-probe"
/usr/bin/time -l "$SAYTILE_BUFFER_SCRATCH/buffer-probe"
