# Final local verification — no-api.3 / ef2f8f8

Frozen runtime: `ef2f8f84f377197350e6384f79af12a9b56272fd`, tree `126d4e2b2c24ea82f016708c03f9567cb297afab`. Only repository-owned synthetic files, disposable databases and background owned native fixtures are used. No microphone, speaker playback, user document, production archive, cloud key, permission prompt or paid API is involved. RC1 is preserved. `source-before.json` and `probe-binaries.json` bind source and executables. The actual 1800.42-second run, complete-waveform comparison and final source comparison all passed. HEAD stayed unchanged and every recorded source hash matched; see `source-after.json` and `realtime-assessment.json`.

| Verification | Observed result | Evidence and scope |
| --- | --- | --- |
| VAD buffer allocation | PASS; 66.7 MB input, incremental peak RSS 262,144 bytes | `voice-buffer.json`; full-kit accelerated resource check, not a soak |
| Schema-5 storage scale | PASS; 100,000 recordings / 300,000 revisions | `storage-scale/storage-scale.json`; real SQLite FULL writes and Store queries, synthetic metadata |
| Process recovery / migration / rollback | 12 checks PASS | `storage-processes.json`; actual SIGKILL, released Beta/RC1 source, zero implicit upload grants, RC1 refusal, complete stopped backup restore |
| Actual Apple local recognition | 8/8 completed through candidates, unified evidence and dispatchable text | `apple-corpus.json`, `apple-summary.json`; synthetic Mandarin, installed framework only |
| Owned native AX | 9/9 scenarios PASS | `owned-range-summary.json`, `owned-range-probe.log`; real native setters, exact owned-PID selection seam |
| Independent conversion reference | PASS; all 39,690,000 input frames actually supplied, 28,800,000 output frames | `conversion-reference.json`; accelerated fixed-batch AVAudioConverter, excludes VAD and wall-clock claims |
| 30-minute capture + complete waveform | PASS; 28,800,000 / 28,800,000 samples, zero differences | `realtime-assessment.json`; full waveform and SHA256 match, actual 1800.42-second execution |

## Stronger audio acceptance after the confirmed defect

The earlier d4b9dbe run had zero ring overflows and internally consistent WAV/SQLite data but lost 1,486 samples in the middle because a converter call could return buffered output without requesting the newly read input batch. Its historical success is not carried forward. The root cause, reproducible red/green and independent code reviews remain in `../../audio-buffer-ownership/`.

This run uses the fixed worker and an independently converted reference. The reference checks all **4,845 feed calls** accepted their offered input and yields exactly **28,800,000 16 kHz frames**, including **1,494 drained tail frames**. Its hash is `050b5e8b2a4154d34590f79cfb949885cc5195271bc7dd72ff8f4aab27885385`. The final assessor walks recordings chronologically and chunks by ordinal, reads every actual WAV payload, and compares every PCM byte/sample against that reference. It also checks complete reference consumption, frame totals, WAV headers, SQLite integrity, zero implicit grants, ring overflow, process duration and source/input/executable hashes. A normal exit, correct duration or internally consistent archive alone cannot pass this assessment.

`run-conversion-reference.sh` is the exact reference recipe. It reuses the retained converter diagnosis probe, a complete static SaytileKit build and the actual AVAudioConverter. Its fixed-batch input is independently checked for the original `supplied=false` failure condition; it is not accepted merely because it labels itself a reference. Raw repeated reference PCM is retained only in the disposable path identified by the JSON receipt.

One mid-run read-only check compared only the already-closed prefix: **96 chunks / 15,390,720 frames / 961.92 seconds**, and every PCM byte matched the independent reference (`realtime-closed-prefix.json`). That was an early diagnostic; the completed full-run comparison below supersedes its limited prefix scope. One owned-process memory snapshot is separately retained; its timing is not asserted as the cause of the older defect.

## Storage and resource scope

The scale run's 200 partial writes measured **0.106 ms p50 / 0.290 ms p95 / 2.317 ms max**. Search found all 100 expected matches in **143.544 ms**; the last 100-row page took **46.522 ms**; recovery claiming took **23.979 ms**. During 499 metadata cleanup operations, concurrent writes measured **0.366 ms p95 / 0.781 ms max**. This excludes physical bulk audio cleanup and archive UI.

The resource probes link the frozen SwiftPM debug SaytileKit; optimized fixture executables do not make them packaged Release-app energy benchmarks. Packaged-app idle/install/UI results are separate. The memory regression measures bounded allocation; the completed 30-minute result is reported separately below.

## Apple and input boundaries

All eight Apple cases produced local candidates, persisted unified evidence and nonempty dispatchable text. First-text latency was **1.132–1.189 seconds**, median **1.154**; finalization after input **0.030–0.090 seconds**, median **0.044**. Corpus duration **48.703 seconds**; CER remains **0–0.263**, with expected/recognized text and actual errors retained. No asset preparation/download was requested. This proves actual local pipeline operation, not human speech accuracy, cloud connection or dual-expert/GPT superiority.

The nine native AX cases cover UTF-16 growth/shrink repair and continuation, manual edits, selection change, injected target change, refused setter, real first-responder change, reopen with uncertain reserved correction and window closure. Safety counters for full-value writes, key/paste events and unexpected payload stayed zero; no owned fixture/probe activation or clipboard generation change was observed. Source hashes remained unchanged during AX execution. The production foreground resolver and arbitrary third-party application compatibility are not exercised. The historical un-attributed AX safety signal remains UNKNOWN; see `../../local-input/ax-historical-replay/REVIEW.md`.

## Reproduction and input identity

The source is the small committed Tingting-generated synthetic AIFF at `../../intermediate-d4b9dbe/local/realtime-synthetic-source.aiff`, **125,714 bytes**, **60,809 frames at 22,050 Hz**, **2.757778 seconds**. `input-fixture.json` binds SHA256 `d7deb6ef7c7a6cc330fbb4ee82eb2733f82ee7761634e6df55f650037bf0b751`. The original synthesis rate/command was not retained; this retained asset permits byte-identical replay. It is not used as ASR truth, and the repeated 30-minute recorded output is not committed.

Use fresh output/scratch directories to preserve these receipts:

```sh
SAYTILE_BUFFER_SCRATCH=/tmp/saytile-final-ef2f8f8-static scripts/test-audio-buffer-memory.sh
SAYTILE_STORAGE_SCRATCH=/tmp/saytile-final-ef2f8f8-static SAYTILE_STORAGE_OUTPUT=/tmp/saytile-scale-output scripts/test-rc-storage-scale.sh
SAYTILE_STORAGE_SCRATCH=/tmp/saytile-final-ef2f8f8-static python3 scripts/test-rc-storage-processes.py --output /tmp/saytile-storage-processes.json
SAYTILE_CORPUS_BUILD=/tmp/saytile-final-ef2f8f8-realtime scripts/test-audio-corpus.sh
python3 scripts/test-owned-range-native.py --execution-context unsandboxed
SAYTILE_AUDIO_SCRATCH=/tmp/saytile-final-ef2f8f8-realtime scripts/test-audio-realtime.sh evidence/no-api-product/intermediate-d4b9dbe/local/realtime-synthetic-source.aiff 1800
```

`run-realtime-evidence.py` preserves the exact actual-run wrapper and 45-second observations of only its known process and owned database. After exit, `finalize-realtime-evidence.py` performs the source-bound archive and complete-waveform assessment; it is not executed prematurely against active files.

## Completed full-duration and full-waveform result

The production capture probe ran for **1800.42 seconds**, fed all **39,690,000 source frames**, and persisted exactly **28,800,000 target frames at 16 kHz — 1800 seconds**. All **60 recordings / 179 WAV chunks** finished and remained available. Total audio file bytes were **57,607,876**, including WAV headers. The raw textual duration displays `1799.9999999999977` from summing floating-point record durations; the exact integer frame count and full waveform independently establish 1800 seconds.

Every saved PCM sample from beginning through middle to end matched the independently converted reference: **different sample frames = 0**, **first differing sample = null**, reference fully consumed. The concatenated saved PCM and reference both have SHA256:

```text
050b5e8b2a4154d34590f79cfb949885cc5195271bc7dd72ff8f4aab27885385
```

All 22 final assessment checks passed. There were zero ring-dropped frames and no capture failure. Every WAV header and actual payload matched its chunk metadata; recording totals matched all chunk frames. SQLite integrity passed at schema 5. Upload authorization count remained **0**. Input, committed short-source asset, probe binary and frozen source hashes remained unchanged. All owned probe processes exited. The **60 pending ASR entries** are expected because recognition was explicitly disabled, not recognition failures or successful cloud calls.

Process CPU time was **16.02 seconds user + 11.83 seconds system**, equivalent to **1.547% of one CPU** across the run. Forty resource snapshots observed RSS **14,432–17,760 KiB**; `/usr/bin/time` reported peak RSS **18,579,456 bytes** and peak physical footprint **7,193,296 bytes**. These measurements cover this synthetic debug-kit capture path, not cloud-model power consumption or battery drain.

The defect-specific end-to-end condition is now satisfied for this frozen source and synthetic input: the complete capture output is byte-identical to the input's independent conversion reference. This does not certify arbitrary real microphone/device transitions, human speech quality, live cloud credentials, real third-party foreground targets or 24/72-hour stability. Those separate boundaries remain disclosed. No additional 30-minute run is required merely to restate this result.
