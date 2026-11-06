#!/bin/bash
# Reproducible, synthetic-only Mandarin benchmark; Apple assets may be downloaded free of charge.
set -euo pipefail
cd "$(dirname "$0")/.."
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
"$SAYTILE_CORPUS_BUILD/corpus-probe" tests/fixtures/MandarinCorpus.json "$SAYTILE_CORPUS_RUN/audio" "$SAYTILE_CORPUS_RUN/store"
