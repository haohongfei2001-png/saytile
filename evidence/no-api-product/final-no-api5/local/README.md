# no-api.5 local verification

The short checks passed on `702a24b9767826275f650c70f7e118365601a2a8`, tree `f5a357a00b97a246ee5c6ee0a95272738c135c0d`. The 30-minute capture runner is prepared and awaiting the coordinated start after the remaining checks. Its complete-waveform assessment is pending.

| Check | Observed result | Receipt |
| --- | --- | --- |
| VoiceSegmenter memory | 66,700,000 input bytes in 50,000 iterations. Incremental peak RSS 229,376 bytes. | `voice-buffer.json` |
| Process recovery, upgrade and rollback | 12 checks passed using the actual released Beta and RC1 Store code, real SIGKILL, kernel write failure, recovery and complete stopped backup restore. Migrations preserved old rows and audio with zero new upload grants. | `storage-processes.json` |
| Storage scale | 100,000 synthetic recordings and 300,000 revisions at schema 5. The 200 partial writes took 0.101 ms p50, 0.194 ms p95 and 0.946 ms maximum. Search returned the expected 100 matches in 142.97 ms. Concurrent writes during 499 metadata cleanup operations took 0.387 ms p95 and 0.752 ms maximum. | `storage-scale/storage-scale.json` |
| Full conversion reference | The independent AVAudioConverter received all 39,690,000 source frames in 4,845 feed calls. It produced 28,800,000 target frames, including 1,494 drained tail frames. Its PCM SHA-256 is `050b5e8b2a4154d34590f79cfb949885cc5195271bc7dd72ff8f4aab27885385`. | `conversion-reference.json` |
| Source and executable identity | All 205 recorded source hashes, HEAD, tree and the input hash matched before and after the short checks. Six short-check executables have recorded hashes. | `short-source-before.json`, `short-source-after.json`, `probe-binaries.json` |

The Store probe for the package reinstall check is `/tmp/saytile-final-702a24b9-static/probe`. Its SHA-256 is `a79194303c79b318fe57e700ee59e92ee0387586273da153c34ca7984622d243`.

The input is the committed Tingting-generated mono AIFF at `evidence/no-api-product/intermediate-d4b9dbe/local/realtime-synthetic-source.aiff`. It contains 60,809 frames at 22,050 Hz, occupies 125,714 bytes and has SHA-256 `d7deb6ef7c7a6cc330fbb4ee82eb2733f82ee7761634e6df55f650037bf0b751`. The committed file identifies the exact replay input. The original synthesis rate and command are unavailable.

The short probes use the complete frozen SwiftPM debug SaytileKit and disposable local databases. Their resource measurements cover synthetic VoiceSegmenter allocation and SQLite metadata operations. The conversion reference uses accelerated fixed-batch processing. The capture runner will assess all saved WAV payloads, reference consumption, frame counts, SQLite integrity, source and binary identity, elapsed wall time, upload grants and ring overflow after it completes.

The exact short commands were run from this worktree's repository root.

```sh
SAYTILE_BUFFER_SCRATCH=/tmp/saytile-final-702a24b9-static scripts/test-audio-buffer-memory.sh
SAYTILE_STORAGE_SCRATCH=/tmp/saytile-final-702a24b9-static python3 scripts/test-rc-storage-processes.py --output evidence/no-api-product/final-no-api5/local/storage-processes.json
SAYTILE_STORAGE_SCRATCH=/tmp/saytile-final-702a24b9-static SAYTILE_STORAGE_OUTPUT=evidence/no-api-product/final-no-api5/local/storage-scale scripts/test-rc-storage-scale.sh
bash evidence/no-api-product/final-no-api5/local/run-conversion-reference.sh
```
