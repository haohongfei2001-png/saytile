#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
base=$PWD
model=${1:?model}; cohort=${2:?cohort}
app=${SAYTILE_BENCH_APP:-$base/.build/mandarin/installed/Saytile.app}
results=${SAYTILE_BENCH_RESULTS:-$base/evidence/mandarin/runs}
cd "$app/Contents/Resources"
for mode in direct product; do
  "$base/.build/mandarin/Cohort" "$model" "$mode" "$base/evidence/mandarin/$cohort.json" "$base/.build/mandarin/wav" "$base/.build/local-asr/weights" "$app/Contents/Helpers" "$results/$cohort-$model-$mode.jsonl"
done
