# no-api.7 local verification

Frozen runtime `4b97bd89b258fea29a0be61d4bd4c23cb5ab428c`, tree `4aac670d6edfcce0c12ed22fa3cd5c68e66061b9`, passed all eight short-receipt conditions. Its 30-minute capture started on 2026-11-07 at 11:26:45 China Standard Time under PID 19087. The full waveform assessment follows natural exit. The input is the committed Tingting synthetic AIFF identified in `input-fixture.json`, SHA-256 `d7deb6ef7c7a6cc330fbb4ee82eb2733f82ee7761634e6df55f650037bf0b751`.

`run-short-evidence.py` runs the existing VAD allocation, Store process recovery, archive scale and conversion reference checks. It records source, recipe and input hashes before and after the run. The Store check exercises the released Beta and RC1 code, schema migration, SIGKILL recovery and explicit backup restore on disposable fixtures. The scale check uses 100,000 recordings and 300,000 revisions. The independent AVAudioConverter reference consumes 39,690,000 input frames in checked batches and compares its output size to the expected 28,800,000 frames. SwiftPM scratch directories and probe executables use a `/tmp/saytile-no-api7-<revision-prefix>` prefix.

The short checks passed. Store completed 12 process, recovery, migration and rollback checks. VAD processed 66.7 MB with a 245,760-byte peak RSS increase. For 100,000 recordings and 300,000 revisions, the 200 partial writes took 0.165 ms p95, and the expected 100 search matches took 133.163 ms. The reference converter accepted all 4,845 batches and produced 28,800,000 frames, including 1,494 drained tail frames. The reference PCM has SHA-256 `050b5e8b2a4154d34590f79cfb949885cc5195271bc7dd72ff8f4aab27885385`.

The short checks ran from the repository root.

```sh
export SAYTILE_FROZEN_SHA=4b97bd89b258fea29a0be61d4bd4c23cb5ab428c
export SAYTILE_FROZEN_TREE=4aac670d6edfcce0c12ed22fa3cd5c68e66061b9
python3 evidence/no-api7/local/run-short-evidence.py
```

The capture phase follows the coordinated start after local checks and CI. `run-realtime-evidence.py` verifies the matching short receipt, binds the capture PID and binary, and observes its own process and disposable SQLite database every 45 seconds. The underlying capture test runs for 1,800 wall-clock seconds using the audio ring, AVAudioConverter, VAD, journal, WAV chunks and real SQLite persistence. Recognition, microphone input and speaker playback are disabled in this fixture.

After natural exit, `finalize-realtime-evidence.py` applies the existing 23 conditions once. It checks every actual WAV payload in chronological order against the independently converted full reference, consumes the complete reference, and verifies frame counts, headers, source identity, ring loss, SQLite integrity, upload grants and elapsed time. Resource evidence includes sampled RSS and CPU, total process CPU time, peak RSS and physical footprint. The no-api.6 capture has separate receipts under its frozen revision.

```sh
python3 evidence/no-api7/local/run-realtime-evidence.py > evidence/no-api7/local/realtime-monitor.log 2>&1
python3 evidence/no-api7/local/finalize-realtime-evidence.py > evidence/no-api7/local/realtime-assessment.log 2>&1
```
