#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
swift build --scratch-path .build/debug --product SaytileKit
bin=$(swift build --scratch-path .build/debug --show-bin-path)
map="$bin/../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap"
[[ -f "$map" ]] || map="$bin/CAudio.build/module.modulemap"
swiftc -swift-version 6 -parse-as-library -I "$bin" -I "$bin/Modules" -I Sources/CSQLite -Xcc "-fmodule-map-file=$map" -L "$bin" -lSaytileKit -lc++ tests/fixtures/MandarinCohort.swift -o .build/mandarin/Cohort
ditto "$bin/Saytile_SaytileKit.bundle" .build/mandarin/Saytile_SaytileKit.bundle
