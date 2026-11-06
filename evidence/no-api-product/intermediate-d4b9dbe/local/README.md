# Final-source local verification — d4b9dbe

Runtime: `d4b9dbe812b9084f1bf31c1817c7b67095e17fc7`. This directory uses only generated or repository-owned synthetic files, disposable databases and background owned native fixtures. No microphone, speaker output, user document, production archive, cloud credential or paid API was used. RC1 remains unchanged. `source-before.json` binds the source/test/script/package inputs; `probe-binaries.json` binds the compiled probes. The complete-duration run and post-run source comparison passed; HEAD remained unchanged and every recorded source/test/script/package hash matched. `source-after.json` and `realtime-assessment.json` preserve the verdict and checks.

| Check | Current result | Evidence and scope |
| --- | --- | --- |
| Production VAD buffer allocation | PASS; 66,700,000 input bytes, incremental peak RSS 229,376 bytes | `voice-buffer.json`; full SaytileKit linkage, accelerated allocation regression, not a soak |
| Schema-5 storage scale | PASS; 100,000 records / 300,000 revisions | `storage-scale/storage-scale.json`; actual SQLite FULL writes and Store queries, synthetic metadata, no physical bulk audio |
| Process recovery, migration, rollback | 12 checks PASS | `storage-processes.json`; real SIGKILL, Beta/RC1 source upgrades, zero implicit upload grants, RC1 refusal, stopped complete-directory backup restoration |
| Actual Apple local speech | 8/8 completed, candidate + unified + dispatchable | `apple-corpus.json`, `apple-summary.json`; synthetic Mandarin, installed framework only |
| Owned native AX | 9/9 scenarios PASS | `owned-range-summary.json`, `owned-range-probe.log`; exact owned-PID target seam, production foreground resolver excluded |
| Realtime capture | PASS; actual 1800.40 seconds, 60 records / 179 verified WAV chunks | `realtime-assessment.json`, raw run/resource/persistence logs; actual wall-clock ring/converter/VAD/journal/Store, ASR disabled |

## Storage and memory observations

These fixtures link the frozen SaytileKit source through the existing SwiftPM debug build paths. The optimized probe executables do not turn that library build into a Release app benchmark. Packaged-app idle/install/UI evidence is separate.

200 partial writes: p50 **0.104 ms**, p95 **0.185 ms**, maximum **1.112 ms**. Search found the 100 expected matches in **148.905 ms**; a 100-row page took **45.125 ms**; recovery claiming took **22.831 ms**. During 499 metadata cleanup operations, concurrent writes had **0.359 ms p95 / 0.684 ms max**. The scale probe ran for **2.76 seconds**, peak RSS **102,481,920 bytes**. These are one-run measurements, not hardware-independent guarantees.

The memory regression links the complete frozen production package. Peak RSS rose from **10,010,624** to **10,240,000 bytes**, well below its 8 MiB retention threshold. `../../local-input/VOICE-BUFFER-REVIEW.md` preserves the original direct-source red/green evidence and explains the consumed-prefix root cause. The final wall-clock result is reported separately below.

## Apple observations and limits

All eight cases entered actual installed Apple recognition, produced local candidates, persisted unified evidence, and yielded nonempty dispatchable text. First-text latency **1.145–1.192 seconds**, median **1.155**; completion after input ended **0.028–0.169 seconds**, median **0.034**. Corpus duration **48.703 seconds**. Normalized CER ranges **0–0.263**; raw expected and recognized synthetic text is preserved. This is not human speech quality acceptance and does not demonstrate cloud access or dual-ASR/GPT superiority. No asset download was requested.

## Native input and historical boundary

The final nine cases cover growing and shortening exact UTF-16 repair with complex emoji and continuation; user text edit; selection change; injected target change; refusing replacement; real first-responder change; Store close/reopen with an uncertain reserved correction; and window closure. All receiving-field safety counters remained zero, with no clipboard generation change, key/Return/send event or owned fixture/probe activation. Source hashes before and after this run matched. These are real native NSTextView setters and production coordinator/Store/AX access, with target discovery intentionally limited to the injected owned PID.

## Historical AX boundary

The original combined AX safety failure remains **UNKNOWN**, as explained in `../../local-input/ax-historical-replay/REVIEW.md`. A bounded replay of retained historical binaries and current successful fixtures cannot reconstruct missing historical receiver counters. Real third-party foreground target discovery is not exercised here; exact-owned-PID selection is explicit. No release-wide foreground compatibility or root-cause claim follows from these tests.

## Reproducible final commands

The committed scripts are the verification entry points. Use fresh scratch/output paths to preserve this evidence:

```sh
SAYTILE_BUFFER_SCRATCH=/tmp/saytile-final-d4b9dbe-static scripts/test-audio-buffer-memory.sh
SAYTILE_STORAGE_SCRATCH=/tmp/saytile-final-d4b9dbe-static SAYTILE_STORAGE_OUTPUT=/tmp/saytile-storage-output scripts/test-rc-storage-scale.sh
SAYTILE_STORAGE_SCRATCH=/tmp/saytile-final-d4b9dbe-static python3 scripts/test-rc-storage-processes.py --output /tmp/saytile-storage-processes.json
SAYTILE_CORPUS_BUILD=/tmp/saytile-final-d4b9dbe-realtime scripts/test-audio-corpus.sh
python3 scripts/test-owned-range-native.py --execution-context unsandboxed
SAYTILE_AUDIO_SCRATCH=/tmp/saytile-final-d4b9dbe-realtime scripts/test-audio-realtime.sh evidence/no-api-product/final/local/realtime-synthetic-source.aiff 1800
```

`run-realtime-evidence.py` preserves the actual run wrapper, exact synthetic input hash, 45-second process-only resource samples and read-only numeric observations of the owned data directory. It never observes other applications or data.

`input-fixture.json` binds the 125,714-byte, 2.757778-second Tingting-generated Mandarin input and its committed small source asset, `realtime-synthetic-source.aiff`. The original synthesis rate/command was not retained; byte-identical replay uses this asset. The repeated 1800-second recorded output is not committed, and this input is not used as an ASR truth label.

## Completed 30-minute wall-clock run

The actual probe ran for **1800.40 seconds**, producing all **39,690,000 input frames** at 22,050 Hz with **zero ring-dropped frames** and no capture error. It saved **60 recordings / 179 WAV chunks / 57,604,904 bytes**. Every recording finished with available audio. Recognition was disabled, so the **60 pending ASR jobs** are expected; no ASR result or cloud success is implied.

Post-run verification opened only the owned stopped database and audio directory. SQLite integrity passed at schema 5; upload authorization count stayed **0** throughout all observations and at completion. Every WAV's sample rate, channels, bit depth, frame count and actual payload length matched the persisted chunk metadata, and recording totals matched **28,798,514 saved 16 kHz frames**. The saved duration is **1799.907125 seconds**, 0.092875 seconds shorter than requested input duration. This exact observation is retained; the result does **not** claim byte-for-byte or sample-for-sample retention of the entire input stream through conversion and voice segmentation.

The original synthetic input and committed short source asset were byte-identical. The probe executable hash was unchanged; all recorded source hashes and HEAD remained `d4b9dbe812b9084f1bf31c1817c7b67095e17fc7`. The maintained assessment recipe is `finalize-realtime-evidence.py`; it requires completed output and does not equate process exit 0 alone with a pass.

Process CPU time was **17.54 s user + 9.82 s system**, equivalent to **1.52% of one CPU** across this run. Forty 45-second snapshots measured RSS **15,664–17,936 KiB**; `/usr/bin/time` reported peak RSS **19,005,440 bytes** and peak footprint **7,291,600 bytes**. A single owned-process midpoint `vmmap` snapshot is retained. These measurements cover a synthetic, ASR-disabled debug-kit capture probe, not cloud-model energy use, battery drain, real microphone behavior, sleep/lock transitions or 24-hour stability.

All owned probe processes exited. The repeated recorded output stays in its disposable `/tmp` directory and is not committed. No user archive or installed RC1 was changed.
