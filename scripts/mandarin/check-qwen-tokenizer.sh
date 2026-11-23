#!/bin/bash
# Exact pinned upstream versus patched tokenizer; no model inference or network.
set -euo pipefail
cd "$(dirname "$0")/../.."
weights=$1
references=$2
output=$3
scratch=$(mktemp -d /tmp/saytile-tokenizer.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$output"
git -C .build/local-asr/speech-swift show a57702e6f523fa36ac5532d2bdc5f35f701a052c:Sources/AudioCommon/Tokenizer.swift > "$scratch/Base.swift"
python3 - "$scratch/Optimized.swift" <<'PY'
import sys
from pathlib import Path
s=Path('native/LocalASR/.vendor/SpeechKernels/Sources/AudioCommon/Tokenizer.swift').read_text()
s=s.replace('Qwen3Tokenizer','OptimizedTokenizer').replace('TokenizerError','OptimizedTokenizerError').replace('TokenizerProtocol','OptimizedTokenizerProtocol').replace('logTokenizer','logOptimized')
Path(sys.argv[1]).write_text(s)
PY
swiftc -O "$scratch/Base.swift" "$scratch/Optimized.swift" tests/fixtures/QwenTokenizerEquivalence.swift -o "$scratch/compare"
"$scratch/compare" "$weights/vocab.json" "$references" > "$output/comparison.json" 2> "$output/tokenizer.log"
