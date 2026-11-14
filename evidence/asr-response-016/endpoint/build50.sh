#!/bin/bash
# Prepared only. Do not run until the root releases the compute slot.
set -euo pipefail
root=/private/tmp/saytile-response-endpoint50
scratch=/private/tmp/saytile-endpoint50-build
out=/private/tmp/saytile-endpoint50-bin
cd "$root"
mkdir -p "$out"
swift build --scratch-path "$scratch" --product SaytileKit --jobs 2
bin=$(swift build --scratch-path "$scratch" --show-bin-path)
map="$bin/../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap"
[[ -f "$map" ]] || map="$bin/CAudio.build/module.modulemap"
swiftc -swift-version 6 -parse-as-library -I "$bin" -I "$bin/Modules" -I Sources/CSQLite -Xcc "-fmodule-map-file=$map" -L "$bin" -lSaytileKit -lc++ tests/fixtures/MandarinCohort.swift -o "$out/Cohort"
ditto "$bin/Saytile_SaytileKit.bundle" "$out/Saytile_SaytileKit.bundle"
shasum -a 256 "$out/Cohort" "$bin/libSaytileKit.a"
# GPU execution is intentionally not included. Run later from the exact same
# validated App/Contents/Resources for both arms, using its unchanged Helpers.
# "$out/Cohort" qwen-small product MANIFEST_JSON WAV_DIR WEIGHTS_DIR APP_HELPERS NEW_RESULT_JSONL
