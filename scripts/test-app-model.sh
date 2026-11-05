#!/bin/bash
# Compile the production AppModel with an isolated nonactivating integration probe.
# No microphone, system permission prompt, clipboard write, or external target is used.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
SAYTILE_MODEL_BIN_DIR="$(swift build --show-bin-path)"
SAYTILE_MODEL_TEMP="$(mktemp -d /tmp/saytile-model-probe.XXXXXX)"
trap 'rm -rf "$SAYTILE_MODEL_TEMP"' EXIT
swiftc -swift-version 6 -parse-as-library \
  -I "$SAYTILE_MODEL_BIN_DIR" -I Sources/CSQLite \
  -Xcc "-fmodule-map-file=$SAYTILE_MODEL_BIN_DIR/../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap" \
  -L "$SAYTILE_MODEL_BIN_DIR" -lSaytileKit -lc++ \
  Sources/SaytileApp/AppModel.swift tests/fixtures/AppModelProbe.swift \
  -o "$SAYTILE_MODEL_TEMP/probe"
mkdir -p evidence
"$SAYTILE_MODEL_TEMP/probe" 2>&1 | tee evidence/native-app-model.log
