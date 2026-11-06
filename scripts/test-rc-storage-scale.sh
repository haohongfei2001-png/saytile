#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SAYTILE_STORAGE_SCRATCH="${SAYTILE_STORAGE_SCRATCH:-/tmp/saytile-rc-storage}"
SAYTILE_STORAGE_OUTPUT="${SAYTILE_STORAGE_OUTPUT:-evidence/no-api-product/storage-scale}"
mkdir -p "$SAYTILE_STORAGE_SCRATCH" "$SAYTILE_STORAGE_OUTPUT"
# Compile the same complete package as the app; schema 4 is not a standalone
# four-file Store any more. Match test-rc-storage-processes.py's static-library path.
swift build --product SaytileKit --scratch-path "$SAYTILE_STORAGE_SCRATCH/build" -Xswiftc -enable-testing
SAYTILE_STORAGE_BIN="$(swift build --product SaytileKit --scratch-path "$SAYTILE_STORAGE_SCRATCH/build" -Xswiftc -enable-testing --show-bin-path)"
SAYTILE_STORAGE_MODULE_MAP="$SAYTILE_STORAGE_BIN/../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap"
if [[ ! -f "$SAYTILE_STORAGE_MODULE_MAP" ]]; then SAYTILE_STORAGE_MODULE_MAP="$SAYTILE_STORAGE_BIN/CAudio.build/module.modulemap"; fi
test -f "$SAYTILE_STORAGE_MODULE_MAP"
swiftc -O -swift-version 6 -parse-as-library -I Sources/CSQLite \
  -I "$SAYTILE_STORAGE_BIN" -I "$SAYTILE_STORAGE_BIN/Modules" \
  -Xcc "-fmodule-map-file=$SAYTILE_STORAGE_MODULE_MAP" \
  -L "$SAYTILE_STORAGE_BIN" -lSaytileKit -lc++ \
  tests/fixtures/StoreScaleProbe.swift -o "$SAYTILE_STORAGE_SCRATCH/scale-probe"
if [[ "${SAYTILE_STORAGE_COMPILE_ONLY:-0}" == 1 ]]; then
  printf 'STORAGE_SCALE_COMPILE_PASS runtime=NOT_RUN\n'
  exit 0
fi
SAYTILE_SCALE_FIXTURE="$(mktemp -d "$SAYTILE_STORAGE_SCRATCH/scale.XXXXXX")"
trap 'rm -rf "$SAYTILE_SCALE_FIXTURE"' EXIT
/usr/bin/time -l "$SAYTILE_STORAGE_SCRATCH/scale-probe" "$SAYTILE_SCALE_FIXTURE" 100000 \
  2> "$SAYTILE_STORAGE_OUTPUT/storage-scale-resources.log" | tee "$SAYTILE_STORAGE_OUTPUT/storage-scale.json"
