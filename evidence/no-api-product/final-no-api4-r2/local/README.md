# Local verification — no-api.4 r2 / 1067f1ad

Frozen source: `1067f1ad5c5c29c698f346651c965db2169625eb`, tree `1c59b5e95f92dd34b19d4fb390549724071114a6`.

All requested short checks and the authorized single 1800-second wall-clock run **PASSED**. Actual execution lasted **1800.48 seconds**. Every saved PCM sample matched the independent full conversion reference, with **zero differences across 28,800,000 samples**. All **23 final assessment checks** passed (the original 22 plus explicit frozen-HEAD equality). This is the complete **1067f1ad engineering baseline**, not an overall product READY declaration; the subsequently approved visual work is separate. The intentionally stopped a6849128 run and its original logs remain unchanged in `../../final-no-api4/local/`.

Only committed synthetic input and disposable databases are used. No microphone, speaker playback, cloud request, private preference, production database, external app target or permission prompt is involved. `short-source-before.json` binds the complete Sources/tests/scripts/packaging/Package.swift file hashes and synthetic input. Only evidence-local output/recipes are written; runtime and test sources remain frozen.

The preserved source AIFF is `evidence/no-api-product/intermediate-d4b9dbe/local/realtime-synthetic-source.aiff` (SHA256 `d7deb6ef7c7a6cc330fbb4ee82eb2733f82ee7761634e6df55f650037bf0b751`, 125,714 bytes; 60,809 mono frames at 22,050 Hz). It was generated with macOS Tingting; the original exact synthesis command/rate was not retained. The retained bytes permit exact replay; its text is not an ASR truth label for these capture tests.

| Check | Result | Evidence |
| --- | --- | --- |
| VAD buffer allocation | PASS; 66.7 MB input / 50,000 iterations; peak RSS increment 262,144 bytes | `voice-buffer.json` |
| Schema-5 storage scale | PASS; 100,000 recordings / 300,000 revisions | `storage-scale/storage-scale.json` |
| Process recovery / migration / rollback | 12 PASS; actual SIGKILL, released Beta/RC1 data preserved, zero implicit grants, RC1 refusal and complete stopped backup restore | `storage-processes.json` |
| Independent accelerated conversion reference | PASS; all 39,690,000 source frames supplied in 4,845 calls; 28,800,000 output frames, including 1,494 drained tail frames | `conversion-reference.json` |
| Source / executable identity | PASS; HEAD and complete source hashes unchanged across short checks and long run; all seven recorded executable hashes unchanged after exit | `short-source-before.json`, `short-source-after.json`, `source-before.json`, `source-after.json`, `probe-binaries.json`, `post-run-identities.json` |
| 30-minute wall-clock capture / complete saved waveform | PASS; actual 1800.48s; 28,800,000 saved samples equal full reference, zero differences | `realtime-assessment.json`, `realtime-assessment.log`, original run/resources/persistence receipts |

Both the independent reference and concatenated saved PCM have SHA256 `050b5e8b2a4154d34590f79cfb949885cc5195271bc7dd72ff8f4aab27885385`. The final assessor establishes this equality from every actual WAV payload, rather than assuming it from a conversion reference alone. The Store probe available for separate isolated reinstall checks is `/tmp/saytile-final-1067f1ad-static/probe`, SHA256 `5e298d7f25f0f3112006783c3ddc7c2bf18b90b9239de5c9341ba72fcbe33aab`.

The 200 partial writes measured 0.102 ms p50 / 0.211 ms p95 / 1.070 ms maximum. Search found 100 expected matches in 143.866 ms. During 499 metadata cleanup operations, concurrent writes measured 0.358 ms p95 / 0.545 ms maximum. This is actual SQLite FULL-write/Store behavior over synthetic metadata, not physical bulk audio deletion or archive UI latency.

## Reproduction and boundaries

From the repository root:

```sh
SAYTILE_BUFFER_SCRATCH=/tmp/saytile-final-1067f1ad-static scripts/test-audio-buffer-memory.sh
SAYTILE_STORAGE_SCRATCH=/tmp/saytile-final-1067f1ad-static python3 scripts/test-rc-storage-processes.py --output evidence/no-api-product/final-no-api4-r2/local/storage-processes.json
SAYTILE_STORAGE_SCRATCH=/tmp/saytile-final-1067f1ad-static SAYTILE_STORAGE_OUTPUT=evidence/no-api-product/final-no-api4-r2/local/storage-scale scripts/test-rc-storage-scale.sh
bash evidence/no-api-product/final-no-api4-r2/local/run-conversion-reference.sh
# Authorized and started after all coordinated short checks and CI passed:
python3 evidence/no-api-product/final-no-api4-r2/local/run-realtime-evidence.py
# Only after that complete capture process exits:
python3 evidence/no-api-product/final-no-api4-r2/local/finalize-realtime-evidence.py
```

Probes link the full frozen SwiftPM debug SaytileKit, while the fixture executables use their existing optimization flags. They are not packaged Release-app battery benchmarks. VAD memory and conversion reference are accelerated checks, not endurance tests. The completed final assessor requires every saved WAV payload to match the independent full reference, plus complete reference consumption, total frame counts, headers/SQLite, no ring loss, no implicit upload grants, actual elapsed duration and source/input/binary identity. A short successful run or internally consistent database cannot replace that assessment.

An initial evidence-bookkeeping read ran before the scale executable had finished building and therefore found no scale output; it wrote no success receipt and did not restart the test. The single scale invocation subsequently exited zero, and the completed results and source/binary hashes above were collected afterwards. Raw test logs are retained.

## Completed wall-clock and complete-waveform assessment

The sole capture process (PID 88336) completed naturally with exit zero after **1800.48 seconds**, produced all **39,690,000 input frames**, and persisted exactly **28,800,000 mono 16 kHz frames**, or **1800 seconds**. All **60 recordings / 179 WAV chunks** finished and remained available; total audio files occupy **57,607,876 bytes**, including headers. The text summary's `1799.9999999999977` seconds is floating-point summation; exact integer sample counts and full-byte comparison independently establish the duration.

The independently converted reference received all source frames and all 4,845 offered batches. The final assessor read every stored WAV payload in chronological recording/chunk order. **Different sample frames: 0; first differing sample: null; reference fully consumed.** Beginning, middle and tail therefore all match, rather than relying only on ring-overflow counters or plausible durations. No intermediate prefix comparison was executed; the copied helper was not used. The complete final assessment was run once after process exit.

All WAV headers and actual payload lengths matched SQLite chunk metadata, all recording frame totals matched their chunks, SQLite integrity passed at schema 5, ring-dropped frames were zero, and upload grants remained **0**. The **60 pending ASR entries** are expected because recognition was explicitly disabled; they do not represent failed or successful cloud recognition. Input bytes, frozen HEAD, all captured source hashes, capture binary and all seven recorded probe binaries remained unchanged. `post-run-identities.json` confirms the owned capture process exited.

Resource measurement comprised **40** 45-second snapshots: RSS **15,136–18,512 KiB**, sampled process CPU **0.4–1.9%**. `/usr/bin/time` reported **14.10 seconds user + 8.83 seconds system**, equivalent to **1.274% of one CPU** across the wall-clock duration; peak RSS **18,989,056 bytes** and peak physical footprint **7,111,376 bytes**. These figures cover the synthetic debug-kit capture path, not live cloud services, packaged Release-app battery drain or real device transitions.

The complete audio-continuity condition is satisfied for this source and synthetic input. This does not certify actual microphone/environmental speech, recognition accuracy, cloud credentials, external foreground insertion, physical display/device changes, 24/72-hour operation, or the newly approved UI's final quality. The result is retained as an engineering baseline while that separate product work continues; no RC1 replacement or overall READY claim follows from it.
