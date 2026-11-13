#!/bin/bash
# Prove network denial inside the tested process, and keep all writes in a fresh temporary archive.
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ $# != 3 || ! -f "$1" || ! -d "$2" ]]; then
  echo "Usage: $0 PUBLIC_FIXTURE.wav VERIFIED_QWEN_SMALL_DIRECTORY RECEIPT.json" >&2
  exit 64
fi
fixture=$1
weights=$2
receipt=$3
scratch=${SAYTILE_MODEL_SCRATCH:-/private/tmp/saytile-offline-model-build}
swift build --scratch-path "$scratch"
bin=$(swift build --scratch-path "$scratch" --show-bin-path)
module_map="$bin/../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap"
[[ -f "$module_map" ]] || module_map="$bin/CAudio.build/module.modulemap"
tmp=$(mktemp -d /private/tmp/saytile-network-denied-XXXXXXXX)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/fresh"
ditto "$bin/Saytile_SaytileKit.bundle" "$tmp/Saytile_SaytileKit.bundle"
swiftc -swift-version 6 -parse-as-library -module-cache-path "$scratch/probe-module-cache" \
  -I "$bin" -I "$bin/Modules" -I Sources/CSQLite -Xcc "-fmodule-map-file=$module_map" \
  -L "$bin" -lSaytileKit -lSaytileVoiceUI -lc++ Sources/SaytileApp/AppModel.swift \
  tests/fixtures/OfflineLocalModelProbe.swift -o "$tmp/OfflineLocalModelProbe"
sandbox-exec -p '(version 1)(allow default)(deny network*)' "$tmp/OfflineLocalModelProbe" \
  "$tmp/fresh" "$fixture" "$weights" "$receipt"
