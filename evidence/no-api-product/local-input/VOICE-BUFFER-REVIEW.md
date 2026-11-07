# Continuous audio buffer retention: confirmed defect and bounded fix

The interrupted realtime run at `3f49682c77c7c80beba3d2075c99ae32c0455c04` revealed retained allocation in `VoiceSegmenter.pending`. `Data.removeFirst(640)` reduces the visible count, but its slice retains the consumed prefix. Repeated appends consequently retain roughly the total input duration even though `pending.count` remains below 640. Memory compression made resident-set samples alone an unreliable verdict.

The fix makes an independent raw-byte copy of the remaining incomplete frame after each `accept` call. This copies at most 639 bytes and releases the lifetime prefix; VAD, preroll, sample ordering and segment thresholds are unchanged.

## Reproduction and observed result

`tests/fixtures/AudioBufferMemoryProbe.swift` runs the actual production `VoiceSegmenter`, including WebRTC VAD, with a deliberately unaligned 1,334-byte synthetic PCM chunk. After 100 warmup calls, 50,000 calls feed 66,700,000 bytes. Peak resident-set growth must stay below 8 MiB. This is an accelerated allocation regression, **not** a wall-clock soak, microphone test or recognition-quality result. The constant input did not trigger speech (`vad_emitted_bytes=0`); native audio tests and the subsequent complete soak cover separate output/persistence behavior.

| Production implementation | Peak RSS before | Peak RSS after | Growth | Result |
| --- | ---: | ---: | ---: | --- |
| Before tail compaction | 6,225,920 | 74,711,040 | 68,485,120 bytes | FAIL |
| After tail compaction | 6,127,616 | 6,373,376 | 245,760 bytes | PASS |

Raw results are `voice-buffer-red.json` and `voice-buffer-green.json`; `voice-buffer-identity.json` binds the old source revision, changed source, same probe and both executable hashes. Those two runs directly compiled `AudioJournal.swift` plus the probe and the already-built, unchanged CAudio object files. They do not claim a final full-package build.

The committed full-package reproduction entry point is:

```sh
SAYTILE_BUFFER_SCRATCH=/tmp/saytile-buffer-check scripts/test-audio-buffer-memory.sh \
  > /tmp/saytile-buffer-check.json 2> /tmp/saytile-buffer-check-build-and-resources.log
```

To reproduce the original direct-source red/green comparison without changing the checkout, build the package once using the script above, export the old source to a disposable file, then compile that old source and the current source with the same probe and CAudio objects. The recorded direct-source runs used `/tmp/saytile-final-3f49682c-realtime/arm64-apple-macosx/debug/CAudio.build`; the equivalent fresh commands are:

```sh
mkdir -p /tmp/saytile-buffer-comparison
git show 3f49682c:Sources/SaytileKit/AudioJournal.swift > /tmp/saytile-buffer-comparison/AudioJournal-before.swift
audio_build=/tmp/saytile-buffer-check/build/arm64-apple-macosx/debug/CAudio.build
for variant in before after; do
  audio_source=/tmp/saytile-buffer-comparison/AudioJournal-before.swift
  if [ "$variant" = after ]; then audio_source=Sources/SaytileKit/AudioJournal.swift; fi
  swiftc -O -swift-version 6 -parse-as-library -I Sources/CAudio/include \
    -Xcc "-fmodule-map-file=$audio_build/module.modulemap" \
    "$audio_source" tests/fixtures/AudioBufferMemoryProbe.swift \
    "$audio_build"/*.o "$audio_build"/webrtc/common_audio/signal_processing/*.o \
    "$audio_build"/webrtc/common_audio/vad/*.o "$audio_build"/webrtc/rtc_base/*.o \
    -lc++ -o "/tmp/saytile-buffer-comparison/$variant"
  "/tmp/saytile-buffer-comparison/$variant" > "/tmp/saytile-buffer-comparison/$variant.json"
done
```

The `before` invocation intentionally exits 1. Run the comparison in a shell without `set -e`, or handle that expected exit explicitly. The module-map layout can differ under another SwiftPM build system; the maintained full-package script resolves both supported locations.

## Historical soak and migration scope

The prior real-time process was explicitly stopped at **904.25 seconds**; all raw evidence moved to `../intermediate-3f49682c/`. It is not a successful 1800-second result. The next final-source soak must run the complete duration after the new source freeze.

The independent storage scripts now require schema 5 and explicitly assert that migrated/local recordings have zero rows in `recording_cloud_authorizations`. All old table columns, rows and audio hashes remain compared exactly during migration; new schema tables are allowed, old content is not relaxed. RC1 must refuse the newer schema without mutation, and rollback uses a stopped complete-directory backup while preserving the upgraded directory. Historical schema-4 baseline evidence remains unchanged. Python AST parsing, shell syntax and the owned diff checks passed; fresh schema-5 process/scale/package tests await the next frozen source.
