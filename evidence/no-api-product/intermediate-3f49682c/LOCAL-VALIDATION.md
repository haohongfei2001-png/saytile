# Frozen-source local acceptance

Runtime source: `3f49682c77c7c80beba3d2075c99ae32c0455c04`. `source-before.json` records the commit/tree and 145 source, script and fixture hashes. `probe-binaries.json` binds the compiled storage, Apple and realtime probes; the native AX summary independently records its source and binary hashes. Subsequent test-only CI timing corrections do not change these runtime inputs. No microphone, speaker playback, real document, production database, API credential, paid endpoint or permission prompt was used; RC1 was preserved.

| Check | Observed outcome | Evidence and limit |
| --- | --- | --- |
| Schema-4 scale | 100,000 recordings / 300,000 revisions; 200 partial writes; PASS | `storage-scale/storage-scale.json`; synthetic metadata, excludes actual audio payloads and UI |
| Recovery / upgrade / rollback | 12 checks PASS | `storage-processes.json`; real child-process SIGKILL, released Beta/RC1 storage source, stopped owned backup, RC1 refuses schema 4, explicit backup restore preserves newer data |
| Owned native AX | 9 scenarios PASS | `owned-range-summary.json`, `owned-range-probe.log`; real background NSTextView setters, injected exact-owned-PID selector; production foreground resolver NOT_RUN |
| Actual Apple local speech | 8 / 8 completed through candidate + fusion + dispatchable revision | `apple-corpus.json`; actual installed Apple framework, synthetic files only; recognition errors retained |
| 30-minute realtime capture | RUNNING; no final verdict yet | `realtime-run.log`, `realtime-resources.jsonl`; actual wall-clock pacing, ASR disabled |

## Storage scale

Partial-write p50 / p95 / max: **0.119 / 0.292 / 2.703 ms**. Search across the seeded archive found all 100 expected matches in **333.738 ms**; the last 100-row page took **97.064 ms**. Recovery claim took **31.317 ms**. During 499 metadata cleanup operations, concurrent draft writes had **0.487 ms p95 / 3.873 ms max**. Probe runtime was **3.21 seconds**, maximum resident set **102,514,688 bytes**. These are one-run measurements on this Mac, not guarantees for other hardware or physical bulk audio deletion.

## Native input

The 9 cases cover growing and shortening an exact UTF-16 correction (including complex emoji), continuation without repeated prefix, user edit, selection change, injected target change, refused setter, real first-responder change, Store reopen with an uncertain reserved correction, and window closure. Safety counters were zero for full-value writes, key events, paste and unexpected payload; no owned fixture/probe activation was observed. Sources did not change during the run.

This current pass does not explain or erase the earlier un-attributed native safety signal preserved in historical evidence. It does not certify arbitrary third-party application focus discovery or a foreground workflow.

## Apple recognition

All eight existing Mandarin corpus cases completed, with 21–31 local candidates per case. First-text latency was **1.127–1.218 seconds** (median **1.170**); completion after input ended was **0.032–0.079 seconds** (median **0.048**). Total synthetic source duration was **48.703 seconds**.

Actual errors remain: `Mac` → `免`, `保存原音` → `保存原因`, `充电器` → `空电视`, and errors within `修改开始时间`. Per-case normalized CER ranges from **0 to 0.263**. Numeric formatting is not canonicalized, so differences such as “三点” versus `3:00` count as edits. This is local pipeline evidence, not human speech quality acceptance, live cloud access or proof that dual experts/GPT outperform a single recognizer.

## Realtime scope

The existing `AudioRealtimeProbe` feeds the production ring/converter/VAD/capture worker/journal/Store at source sample timing for 1800 seconds. Recognition is explicitly disabled. `realtime-resources.jsonl` samples only the known owned process PID every 45 seconds; `realtime-persistence.jsonl` contains read-only numeric snapshots of only its disposable database. No other application or user data is observed. The final runtime, dropped-frame count, saved audio availability and completion status must be assessed after the probe exits.
