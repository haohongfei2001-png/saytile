#!/bin/bash
# Wall-clock synthetic stream only. Does not open microphones or output audio.
set -euo pipefail
cd "$(dirname "$0")/.."
SAYTILE_AUDIO_SCRATCH="${SAYTILE_AUDIO_SCRATCH:-/tmp/saytile-rc-audio}"
SAYTILE_AUDIO_FIXTURE="${1:?Pass an explicitly synthetic mono AIFF fixture}"
SAYTILE_AUDIO_SECONDS="${2:-1800}"
SAYTILE_AUDIO_DATA="$(mktemp -d /tmp/saytile-rc-realtime-data.XXXXXX)"
swift build --scratch-path "$SAYTILE_AUDIO_SCRATCH" --build-system native --target SaytileKit
SAYTILE_AUDIO_BIN="$SAYTILE_AUDIO_SCRATCH/arm64-apple-macosx/debug"
swiftc -parse-as-library -I "$SAYTILE_AUDIO_BIN/Modules" -I Sources/CAudio/include \
  -Xcc -fmodule-map-file=Sources/CSQLite/module.modulemap \
  -Xcc "-fmodule-map-file=$SAYTILE_AUDIO_BIN/CAudio.build/module.modulemap" \
  tests/fixtures/AudioRealtimeProbe.swift "$SAYTILE_AUDIO_BIN"/SaytileKit.build/*.o \
  "$SAYTILE_AUDIO_BIN"/CAudio.build/*.o \
  "$SAYTILE_AUDIO_BIN"/CAudio.build/webrtc/common_audio/signal_processing/*.o \
  "$SAYTILE_AUDIO_BIN"/CAudio.build/webrtc/common_audio/vad/*.o \
  "$SAYTILE_AUDIO_BIN"/CAudio.build/webrtc/rtc_base/*.o \
  -lsqlite3 -lc++ -o "$SAYTILE_AUDIO_SCRATCH/realtime-probe"
printf 'Scope: synthetic realtime ring, converter, VAD, journal, SQLite; ASR disabled; no microphone/speaker\n'
printf 'Data directory: %s\n' "$SAYTILE_AUDIO_DATA"
/usr/bin/time -l "$SAYTILE_AUDIO_SCRATCH/realtime-probe" "$SAYTILE_AUDIO_FIXTURE" "$SAYTILE_AUDIO_SECONDS" "$SAYTILE_AUDIO_DATA"
