# no-api.5 final integration local verification

The short checks and single 30-minute capture passed on `4df87ad4dd7ff94da2027f0c978ca5c5cb1d7292`, tree `ce2a3fed6a27a96ed4dca80abeac307793d4e705`. The capture ran for 1800.54 seconds. All 23 final conditions passed. The 28,800,000 saved samples match the independent conversion reference byte for byte.

| Check | Observed result | Receipt |
| --- | --- | --- |
| VoiceSegmenter memory | 66,700,000 input bytes in 50,000 iterations. Incremental peak RSS 245,760 bytes. | `voice-buffer.json` |
| Process recovery, upgrade and rollback | 12 checks passed using the actual released Beta and RC1 Store code, real SIGKILL, kernel write failure, recovery and complete stopped backup restore. Migrations preserved old rows and audio with zero new upload grants. | `storage-processes.json` |
| Storage scale | 100,000 synthetic recordings and 300,000 revisions at schema 5. The 200 partial writes took 0.114 ms p50, 0.303 ms p95 and 1.181 ms maximum. Search returned the expected 100 matches in 135.63 ms. Concurrent writes during 499 metadata cleanup operations took 0.326 ms p95 and 0.744 ms maximum. | `storage-scale/storage-scale.json` |
| Full conversion reference | The independent AVAudioConverter received all 39,690,000 source frames in 4,845 feed calls. It produced 28,800,000 target frames, including 1,494 drained tail frames. Its PCM SHA-256 is `050b5e8b2a4154d34590f79cfb949885cc5195271bc7dd72ff8f4aab27885385`. | `conversion-reference.json` |
| Source and executable identity | All 205 recorded source hashes, HEAD, tree and the input hash matched. The six short-check executables and capture probe all matched their recorded hashes after capture. | `short-source-before.json`, `short-source-after.json`, `source-before.json`, `source-after.json`, `probe-binaries.json`, `post-run-identities.json` |
| Wall-clock capture and full waveform | 1800.54 seconds. All 179 WAV payloads matched the 28,800,000-frame reference. Differing samples 0. | `realtime-start.json`, `realtime-run.log`, `realtime-assessment.json`, `realtime-assessment.log` |

The Store probe for the package reinstall check is `/tmp/saytile-final-4df87ad4-static/probe`. Its SHA-256 is `07e6fd071a989eac7e76c8e5eb59a78233e1a56a6ec3248dcff3a945535ad54b`.

The input is the committed Tingting-generated mono AIFF at `evidence/no-api-product/intermediate-d4b9dbe/local/realtime-synthetic-source.aiff`. It contains 60,809 frames at 22,050 Hz, occupies 125,714 bytes and has SHA-256 `d7deb6ef7c7a6cc330fbb4ee82eb2733f82ee7761634e6df55f650037bf0b751`. The committed file identifies the exact replay input. The original synthesis rate and command are unavailable.

The short probes use the complete frozen SwiftPM debug SaytileKit and disposable local databases. Their resource measurements cover synthetic VoiceSegmenter allocation and SQLite metadata operations. The conversion reference uses accelerated fixed-batch processing. The final assessor verified every saved WAV payload, reference consumption, frame counts, SQLite integrity, source and binary identity, elapsed wall time, upload grants and ring overflow in a single pass after the capture process exited.

The exact short commands were run from this worktree's repository root.

```sh
SAYTILE_BUFFER_SCRATCH=/tmp/saytile-final-4df87ad4-static scripts/test-audio-buffer-memory.sh
SAYTILE_STORAGE_SCRATCH=/tmp/saytile-final-4df87ad4-static python3 scripts/test-rc-storage-processes.py --output evidence/no-api-product/final-no-api5-r2/local/storage-processes.json
SAYTILE_STORAGE_SCRATCH=/tmp/saytile-final-4df87ad4-static SAYTILE_STORAGE_OUTPUT=evidence/no-api-product/final-no-api5-r2/local/storage-scale scripts/test-rc-storage-scale.sh
bash evidence/no-api-product/final-no-api5-r2/local/run-conversion-reference.sh
```

## Wall-clock capture results

The capture process started at 09:47:15 China Standard Time on 2026-11-07. PID 28472 used the synthetic input bound by `input-fixture.json` and the disposable database under `/tmp/saytile-rc-realtime-data.uWRU2j`. The capture probe SHA-256 is `4dbc6218c02be0302fe9c45a62e6cc4429ce3e09b44f28b19ad44f1be5a6568a`. The process exited naturally with status zero. The 32.94-second build preceded the 1800.54-second capture measurement.

The producer supplied 39,690,000 source frames. The archive contains 60 finished recordings and 179 available WAV chunks totaling 57,607,876 bytes including headers. All WAV headers, actual payload lengths, per-chunk database counts and total recording frames agree. The exact integer count is 28,800,000 mono frames at 16,000 Hz, or 1800 seconds. The raw summary's `1799.9999999999977` seconds results from adding floating-point durations.

The comparison consumed the entire independent reference. The concatenated saved PCM and reference share SHA-256 `050b5e8b2a4154d34590f79cfb949885cc5195271bc7dd72ff8f4aab27885385`. The number of differing frames is zero. SQLite passed its integrity check at schema 5. Ring overflow and upload grants both remained zero. Recognition was disabled for this capture, which left 60 ASR entries pending.

The monitor recorded 40 resource samples and 40 database observations. All observations completed successfully. Sampled RSS ranged from 15,504 to 18,704 KiB, and sampled CPU ranged from 0.4% to 2.6%. `/usr/bin/time` measured 18.04 seconds of user CPU and 12.73 seconds of system CPU, equivalent to 1.709% of one CPU over the full capture. Peak RSS was 19,185,664 bytes and peak physical footprint was 7,193,296 bytes. These figures describe the synthetic debug-kit capture process. Real microphone, device transitions, cloud recognition and longer endurance have separate verification scopes.

The wall-clock driver and final assessor were each executed once.

```sh
python3 evidence/no-api-product/final-no-api5-r2/local/run-realtime-evidence.py
python3 evidence/no-api-product/final-no-api5-r2/local/finalize-realtime-evidence.py
```
