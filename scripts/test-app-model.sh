#!/bin/bash
# Compile the production AppModel with an isolated nonactivating integration probe.
# No microphone, system permission prompt, clipboard write, or external target is used.
set -euo pipefail
cd "$(dirname "$0")/.."
SAYTILE_MODEL_SCRATCH="${SAYTILE_MODEL_SCRATCH:-/tmp/saytile-rc-model}"
SAYTILE_MODEL_COMMAND=(swift build --scratch-path "$SAYTILE_MODEL_SCRATCH")
if [[ "${SAYTILE_SWIFT_DISABLE_SANDBOX:-0}" == 1 ]]; then SAYTILE_MODEL_COMMAND+=(--disable-sandbox); fi
if [[ -n "${SAYTILE_MODEL_BUILD_SYSTEM:-}" ]]; then SAYTILE_MODEL_COMMAND+=(--build-system "$SAYTILE_MODEL_BUILD_SYSTEM"); fi
"${SAYTILE_MODEL_COMMAND[@]}"
SAYTILE_MODEL_BIN_DIR="$("${SAYTILE_MODEL_COMMAND[@]}" --show-bin-path)"
# SwiftBuild (CLT) and SwiftPM (Xcode CI) use different module layouts.
SAYTILE_MODEL_MODULE_MAP="$SAYTILE_MODEL_BIN_DIR/../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap"
if [[ ! -f "$SAYTILE_MODEL_MODULE_MAP" ]]; then
  SAYTILE_MODEL_MODULE_MAP="$SAYTILE_MODEL_BIN_DIR/CAudio.build/module.modulemap"
fi
[[ -f "$SAYTILE_MODEL_MODULE_MAP" ]] || { printf 'CAudio module map missing\n' >&2; exit 1; }
SAYTILE_MODEL_TEMP="$(mktemp -d /tmp/saytile-model-probe.XXXXXX)"
trap 'rm -rf "$SAYTILE_MODEL_TEMP"' EXIT
if [[ -d "$SAYTILE_MODEL_BIN_DIR/Saytile_SaytileKit.bundle" ]]; then
  ditto "$SAYTILE_MODEL_BIN_DIR/Saytile_SaytileKit.bundle" "$SAYTILE_MODEL_TEMP/Saytile_SaytileKit.bundle"
fi
swiftc -swift-version 6 -parse-as-library -module-cache-path "$SAYTILE_MODEL_SCRATCH/probe-module-cache" \
  -I "$SAYTILE_MODEL_BIN_DIR" -I "$SAYTILE_MODEL_BIN_DIR/Modules" -I Sources/CSQLite \
  -Xcc "-fmodule-map-file=$SAYTILE_MODEL_MODULE_MAP" \
  -L "$SAYTILE_MODEL_BIN_DIR" -lSaytileKit -lc++ \
  Sources/SaytileApp/AppModel.swift tests/fixtures/AppModelProbe.swift \
  -o "$SAYTILE_MODEL_TEMP/probe"
SAYTILE_MODEL_LOG="${SAYTILE_MODEL_LOG:-evidence/native-app-model.log}"
mkdir -p "$(dirname "$SAYTILE_MODEL_LOG")"
"$SAYTILE_MODEL_TEMP/probe" 2>&1 | tee "$SAYTILE_MODEL_LOG"
