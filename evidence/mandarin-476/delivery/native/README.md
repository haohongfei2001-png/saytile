# 476 original-rate native acceptance

Candidate source is `0fbca1d892bbc8aa550c4439b8cfcb045af825ae`, build 0.13 (476). The installed baseline is `0dc6ed70e873ec41da3b1dd24f47350a91211a43`, 0.13 (474). Runs use the same original-rate public PCM, local Qwen 0.6B weights, automatic route, isolated profiles, SQLite, and the signed app's actual AppKit panel. Only one ASR worker runs. The M5 lid stayed closed. The microphone was not opened.

## Outcome

* PASS for repeated native updates on all 15 short inputs and both long inputs, unchanged complete final archives on all 17 unique inputs, completed recording states, archive/window equality, and plain final decoding. Every reported final decode had zero verified-prefix tokens.
* PASS for lower combined app/helper CPU in the two adjacent 1.33-core injected-load pairs. The 38.8 s input used 31.95 → 23.68 CPU seconds, and the 25.74 s input used 19.25 → 15.42. External load was still changing, so the exact size of a causal speedup remains uncertain.
* FAIL for the intended fixed-six-core load condition. The identical nine-process load obtained 5.061 / 3.854 / 5.081 cores in the 474 → 476 → 474 sequence. Actual receipts and all recognizer results are retained. A measured six-core performance claim is unsupported.
* NOT_PROVEN for a uniform latency improvement. Short-file first text and final confirmation were slower in this neighboring run. Long-file worst freezes improved in the two lighter pairs, while the heavier sequence remained variable.
* NOT_RUN for live microphone, natural user speech, 8 GB hardware, and direct power/energy measurement.

## Short-file neighboring runs

The candidate ran first, followed by the baseline immediately afterwards. Both process the same 15 inputs and produce byte-identical final archives, with **46 errors / 568 reference units (8.099% CER)**. Every input has repeated matching-reference updates.

| Measurement | 474 following control | 476 candidate |
|---|---:|---:|
| First literal text P50 / P95, s | 1.105 / 2.038 | 1.348 / 2.303 |
| First matching reference bigram P50 / P95, s | 1.259 / 2.490 | 1.401 / 2.303 |
| Internal matching-bigram update P95, s | 1.061 | 1.093 |
| Internal newly matching word-type update P95, s | 1.371 | 1.474 |
| Longest literal still frame during active speech, s | 2.038 | 2.303 |
| Longest newly matching word-type gap, s | 2.490 | 2.570 |
| EOF-to-archive P50 / P95, s | 0.302 / 1.087 | 0.462 / 1.469 |
| Lexical revisions / replaced characters | 23 / 34 | 20 / 30 |
| Sum of preview decode wall time, s | 51.098 | 41.530 |

Decode wall time measures occupancy and includes waiting. It is separate from the process CPU counters measured on the longer inputs. First text includes per-case engine cold start. These 15 were fresh app/worker processes; continuously resident dictation is a different condition.

## Long-file adjacent pairs

Each longer pair used two extra user-initiated load processes, targeting and attaining 1.33 cores. External activity declined during the four-arm sequence. The long 38.8 s clip concatenates five public utterances, and the 25.74 s sample is FLEURS.

| Measurement | 38.8 s, 474 → 476 | 25.74 s, 474 → 476 |
|---|---:|---:|
| Final reference errors | 31/205 → 31/205 | 5/92 → 5/92 |
| App + helper CPU, s | 31.95 → 23.68 | 19.25 → 15.42 |
| Maximum actual simultaneous physical footprint, MiB | 1255.1 → 1532.3 | 1316.7 → 1382.7 |
| Longest literal still frame, s | 6.873 → 3.170 | 2.735 → 2.154 |
| New matching word-type P95, s | 1.696 → 2.047 | 2.043 → 1.448 |
| Longest new matching word-type gap, s | 6.945 → 4.134 | 2.735 → 2.411 |
| EOF-to-archive, s | 0.723 → 0.594 | 0.761 → 0.297 |
| Lexical revision count | 7 → 9 | 3 → 5 |

## Strong contention sequence

All three use the same nine processes and 38.8 s PCM. The six-core target was missed, as recorded above.

| Measurement | 474 first | 476 | 474 second |
|---|---:|---:|---:|
| Actual added load, CPU cores | 5.061 | 3.854 | 5.081 |
| App + helper CPU, s | 26.09 | 17.52 | 27.56 |
| Longest literal still frame, s | 3.466 | 4.320 | 5.928 |
| Longest new matching word-type gap, s | 3.466 | 4.574 | 7.019 |
| New matching word-type P95, s | 1.740 | 2.000 | 1.522 |
| EOF-to-archive, s | 1.314 | 0.854 | 0.914 |
| Final reference errors | 31/205 | 31/205 | 31/205 |

Actual competition varied enough that this sequence cannot establish a uniform worst-freeze improvement. It does reproduce multi-second gaps in both versions and preserve the independent model, publisher and panel timelines for diagnosis.

## Evidence and scoring

`machine-summary.json` retains every per-input result, source, input checksum, actual added load, timing, revision count, CPU and footprint. `public-native-receipts.tar.gz` retains 111 files including raw worker hypotheses, model timing, published text, visible frame observations, final archives, exact input hashes, load receipts, app/helper CPU samples, and cold-start identities. `SHA256SUMS.json` binds this report and all artifacts.

The scripts are `scripts/mandarin/measure-loaded-preview.py`, `preview-cpu-load.c`, `score-live-cadence.py`, `score-preview-words.py` and `reference-words.swift`. The CER normalizer and reference transcripts are unchanged. Word timing first counts a reference word type once per utterance and does not constitute WER or an ordered complete-word alignment. The tokenizer separates ASCII and non-ASCII runs to avoid a macOS tokenizer omission in mixed sentences. Both sides use the same tokenizer executable.

The earlier quiet 474 baseline remains in the tar for context. Its different machine-load interval cannot serve as the sole control for this candidate. Native timestamps prove visible observations and model publications separately. Text animation cannot increase the model-publication count.
