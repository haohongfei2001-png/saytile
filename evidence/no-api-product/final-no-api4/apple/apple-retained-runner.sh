#!/bin/bash
# Synthetic-only Mandarin benchmark. Existing Apple assets only by default;
# opt in to the separate free asset preparation with SAYTILE_CORPUS_PREPARE=1.
set -euo pipefail
cd '/Users/hhf/.codex/worktrees/saytile-no-api-product'
SAYTILE_CORPUS_BUILD="${SAYTILE_CORPUS_BUILD:-/tmp/saytile-rc-audio}"
SAYTILE_CORPUS_RUN="$(mktemp -d /tmp/saytile-rc-corpus.XXXXXX)"
python3 - "$SAYTILE_CORPUS_RUN" <<'PY'
import json, subprocess, sys
from pathlib import Path
root = Path(sys.argv[1]); (root/'audio').mkdir()
for case in json.load(open('tests/fixtures/MandarinCorpus.json')):
    subprocess.run(['say','-v',case['voice'],'-r','175','-o',str(root/'audio'/f"{case['id']}.aiff"),case['spoken']], check=True)
PY
swift build --scratch-path "$SAYTILE_CORPUS_BUILD" --build-system native --target SaytileKit >&2
SAYTILE_CORPUS_BIN="$SAYTILE_CORPUS_BUILD/arm64-apple-macosx/debug"
swiftc -parse-as-library -I "$SAYTILE_CORPUS_BIN/Modules" -I Sources/CAudio/include \
  -Xcc -fmodule-map-file=Sources/CSQLite/module.modulemap \
  -Xcc "-fmodule-map-file=$SAYTILE_CORPUS_BIN/CAudio.build/module.modulemap" \
  tests/fixtures/AudioCorpusProbe.swift "$SAYTILE_CORPUS_BIN"/SaytileKit.build/*.o \
  "$SAYTILE_CORPUS_BIN"/CAudio.build/*.o \
  "$SAYTILE_CORPUS_BIN"/CAudio.build/webrtc/common_audio/signal_processing/*.o \
  "$SAYTILE_CORPUS_BIN"/CAudio.build/webrtc/common_audio/vad/*.o \
  "$SAYTILE_CORPUS_BIN"/CAudio.build/webrtc/rtc_base/*.o \
  -lsqlite3 -lc++ -o "$SAYTILE_CORPUS_BUILD/corpus-probe"
SAYTILE_CORPUS_COMMAND=("$SAYTILE_CORPUS_BUILD/corpus-probe" tests/fixtures/MandarinCorpus.json "$SAYTILE_CORPUS_RUN/audio" "$SAYTILE_CORPUS_RUN/store")
if [[ "${SAYTILE_CORPUS_PREPARE:-0}" == 1 ]]; then SAYTILE_CORPUS_COMMAND+=(--prepare-speech); fi
printf '%s\n' "$SAYTILE_CORPUS_RUN" > evidence/no-api-product/final-no-api4/apple/fixture-directory.txt
shasum -a 256 "$SAYTILE_CORPUS_BUILD/corpus-probe" > evidence/no-api-product/final-no-api4/apple/binary.before.sha256
"${SAYTILE_CORPUS_COMMAND[@]}"
shasum -a 256 "$SAYTILE_CORPUS_BUILD/corpus-probe" > evidence/no-api-product/final-no-api4/apple/binary.after.sha256
