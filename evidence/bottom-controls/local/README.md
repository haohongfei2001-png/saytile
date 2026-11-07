# no-api.6 local verification

Frozen runtime `455143310222c2c03c4a4888e5df5552c3af4131`, tree `87015ba6c1cb2b38c5a868a2fed1b86b9eaac683`, passed all eight short-receipt conditions. Its 30-minute capture started on 2026-11-07 at 11:01:38 China Standard Time under PID 2613. It completed in 1800.48 seconds. The final assessor passed all 23 conditions, with identical saved and reference PCM across 28,800,000 samples. The input is the committed Tingting synthetic AIFF identified in `input-fixture.json`, SHA-256 `d7deb6ef7c7a6cc330fbb4ee82eb2733f82ee7761634e6df55f650037bf0b751`.

`run-short-evidence.py` runs the existing VAD allocation, Store process recovery, archive scale and conversion reference checks. It records source, recipe and input hashes before and after the run. The Store check exercises the released Beta and RC1 code, schema migration, SIGKILL recovery and explicit backup restore on disposable fixtures. The scale check uses 100,000 recordings and 300,000 revisions. The independent AVAudioConverter reference consumes 39,690,000 input frames in checked batches and compares its output size to the expected 28,800,000 frames. SwiftPM scratch directories and probe executables use a `/tmp/saytile-no-api6-<revision-prefix>` prefix.

The short checks passed. Store completed 12 process, recovery, migration and rollback checks. VAD processed 66.7 MB with a 245,760-byte peak RSS increase. For 100,000 recordings and 300,000 revisions, the 200 partial writes took 0.152 ms p95, and the expected 100 search matches took 121.835 ms. The reference converter accepted all 4,845 batches and produced 28,800,000 frames, including 1,494 drained tail frames. The reference PCM has SHA-256 `050b5e8b2a4154d34590f79cfb949885cc5195271bc7dd72ff8f4aab27885385`.

The short checks ran from the repository root.

```sh
export SAYTILE_FROZEN_SHA=455143310222c2c03c4a4888e5df5552c3af4131
export SAYTILE_FROZEN_TREE=87015ba6c1cb2b38c5a868a2fed1b86b9eaac683
python3 evidence/bottom-controls/local/run-short-evidence.py
```

The capture phase follows the coordinated start after local checks and CI. `run-realtime-evidence.py` verifies the matching short receipt, binds the capture PID and binary, and observes its own process and disposable SQLite database every 45 seconds. The underlying capture test runs for 1,800 wall-clock seconds using the audio ring, AVAudioConverter, VAD, journal, WAV chunks and real SQLite persistence. Recognition, microphone input and speaker playback are disabled in this fixture.

After natural exit, `finalize-realtime-evidence.py` applies the existing 23 conditions once. It checks every actual WAV payload in chronological order against the independently converted full reference, consumes the complete reference, and verifies frame counts, headers, source identity, ring loss, SQLite integrity, upload grants and elapsed time. Resource evidence includes sampled RSS and CPU, total process CPU time, peak RSS and physical footprint. The prior no-api.5 receipts remain at their original paths.

```sh
python3 evidence/bottom-controls/local/run-realtime-evidence.py > evidence/bottom-controls/local/realtime-monitor.log 2>&1
python3 evidence/bottom-controls/local/finalize-realtime-evidence.py > evidence/bottom-controls/local/realtime-assessment.log 2>&1
```

## Complete capture and archive

The producer delivered 39,690,000 source frames. All 60 recordings and 179 WAV chunks finished and remained available. The files occupy 57,607,876 bytes with headers. Every WAV payload was checked in chronological recording/chunk order, with matching headers, SQLite metadata and frame totals. The archive saved 28,800,000 mono 16 kHz samples, exactly 1800 seconds. The float sum in the console is `1799.9999999999977`.

The comparison consumed the full reference. Differing samples were 0. Saved PCM and reference share SHA-256 `050b5e8b2a4154d34590f79cfb949885cc5195271bc7dd72ff8f4aab27885385`. SQLite passed integrity checking at schema 5, the ring reported zero dropped frames, and the upload-grant count remained zero. The 60 pending ASR entries are expected in this recognition-disabled capture.

The probe exited naturally with status zero. Frozen HEAD, all 207 source hashes, the synthetic input and all seven recorded executables retained their identities. The 40 resource samples reported RSS of 14,176–17,952 KiB and CPU of 0.5–2.5%. There were 40 read-only database observations and 0 observation errors. Process CPU totaled 15.55 seconds user plus 10.83 seconds system, or 1.465% of one CPU across the capture. Peak RSS was 18,808,832 bytes and peak physical footprint was 7,193,296 bytes.

The .6 and .7 synthetic runs overlapped for approximately five minutes using distinct executables, databases and output directories. Resource values above measure the identified process. The verification covers the production capture and persistence path using a committed synthetic input and SwiftPM debug library. Live cloud recognition, physical-device audio and human speech quality remain separate acceptance scopes.
