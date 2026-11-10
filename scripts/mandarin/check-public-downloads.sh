#!/bin/bash
# Uses public SHA-pinned weights and disposable directories only.
set -euo pipefail
cd "$(dirname "$0")/../.."
scratch=${SAYTILE_TRANSFER_BUILD:-.build/mandarin-transfer}
swift build --scratch-path "$scratch" --product SaytileKit
bin=$(swift build --scratch-path "$scratch" --show-bin-path)
map="$bin/../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap"
[[ -f "$map" ]] || map="$bin/CAudio.build/module.modulemap"
swiftc -swift-version 6 -parse-as-library -I "$bin" -I "$bin/Modules" -I Sources/CSQLite -Xcc "-fmodule-map-file=$map" -L "$bin" -lSaytileKit -lc++ tests/fixtures/LocalDownloadProbe.swift -o "$bin/MandarinPublicDownload"
for engine in "$@"; do
  echo "Checking $engine at $(git rev-parse HEAD)"
  "$bin/MandarinPublicDownload" "$engine"
done
