# no-api.6 local verification

The procedures are prepared. Measurements begin after the runtime revision and tree are frozen. This directory uses the committed Tingting synthetic AIFF identified in `input-fixture.json`. Its SHA-256 is `d7deb6ef7c7a6cc330fbb4ee82eb2733f82ee7761634e6df55f650037bf0b751`.

`run-short-evidence.py` runs the existing VAD allocation, Store process recovery, archive scale and conversion reference checks. It records source, recipe and input hashes before and after the run. The Store check exercises the released Beta and RC1 code, schema migration, SIGKILL recovery and explicit backup restore on disposable fixtures. The scale check uses 100,000 recordings and 300,000 revisions. The independent AVAudioConverter reference consumes 39,690,000 input frames in checked batches and compares its output size to the expected 28,800,000 frames. SwiftPM scratch directories and probe executables use a `/tmp/saytile-no-api6-<revision-prefix>` prefix.

Once the frozen revision and tree have been supplied, the short checks run from the repository root.

```sh
export SAYTILE_FROZEN_SHA='<full frozen Git commit>'
export SAYTILE_FROZEN_TREE='<full frozen Git tree>'
python3 evidence/bottom-controls/local/run-short-evidence.py
```

The capture phase follows the coordinated start after local checks and CI. `run-realtime-evidence.py` verifies the matching short receipt, binds the capture PID and binary, and observes its own process and disposable SQLite database every 45 seconds. The underlying capture test runs for 1,800 wall-clock seconds using the audio ring, AVAudioConverter, VAD, journal, WAV chunks and real SQLite persistence. Recognition, microphone input and speaker playback are disabled in this fixture.

After natural exit, `finalize-realtime-evidence.py` applies the existing 23 conditions once. It checks every actual WAV payload in chronological order against the independently converted full reference, consumes the complete reference, and verifies frame counts, headers, source identity, ring loss, SQLite integrity, upload grants and elapsed time. Resource evidence includes sampled RSS and CPU, total process CPU time, peak RSS and physical footprint. The prior no-api.5 receipts remain at their original paths.

```sh
python3 evidence/bottom-controls/local/run-realtime-evidence.py > evidence/bottom-controls/local/realtime-monitor.log 2>&1
python3 evidence/bottom-controls/local/finalize-realtime-evidence.py > evidence/bottom-controls/local/realtime-assessment.log 2>&1
```
