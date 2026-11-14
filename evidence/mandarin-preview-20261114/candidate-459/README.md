# Native Mandarin preview acceptance for 0.13 build 459

Product SHA 914b339298e7214f0a38008300fd88a56f9c1a3b. The M5 replay used the automatic, single local Qwen 0.6B engine with the same verified 4-bit weights, public source WAVs and references as build 442. Each WAV was delivered in real time to the signed app, through the product VAD, rolling model, SingleTranscriptEngine, SQLite and AppKit window, with a separate data directory. These measurements do not use a microphone.

| Real native measurement | Build 442 | Build 459 |
| --- | ---: | ---: |
| Final CER, 15 original-speed clips / 568 characters | 46 errors (8.10%) | 46 errors (8.10%) |
| First meaningful screen text P50 / P95 | 0.923 / 1.510 s | 1.101 / 1.514 s |
| Meaningful timeline update interval P50 / P95 | 0.513 / 1.115 s | 0.517 / 1.043 s |
| Meaningful window update interval P50 / P95 | 0.514 / 1.040 s | 0.440 / 1.021 s |
| Longest meaningful timeline gap, same 15 clips | 1.948 s | 1.961 s |
| Archive completion after EOF P50 / P95 | 0.218 / 0.694 s | 0.187 / 0.343 s |
| Screen revisions including punctuation | 151 | 59 |
| Provisional sentence-ending marks withdrawn | 106 | 9 |
| Normalized lexical suffix revisions / affected characters | 26 / 40 | 27 / 41 |

All 15 recordings showed multiple native on-screen updates before the end of their input. All 18 real-time inputs produced character-identical archives on the two builds. The screen comparison excludes timer animations without fresh source text. Short-clip raw compute totals were 29.282 and 29.911 seconds respectively, each over 232 preview decodes. At 1,075 paired wall-clock points, reference-prefix errors per displayed character were 0.10640 and 0.10685. The candidate reduces visible punctuation flicker and the reproducible long-clause hold. It does not establish a lexical preview accuracy gain. [Same-source scoring and raw counts](text-and-cost.json)

The 38.8 s public continuous fixture reproduced a 4.883 s native screen freeze on 442 and a 9.111 s freeze on rejected intermediate 453. On 459 the longest was 1.551 s in the same unmetered native protocol, with the same archived text (31 errors in 205 characters). The 25.74 s reference clip went from 2.080 to 2.032 s, with unchanged 5/92 errors. At 13.53–15.05 s the worker had no new words. The first new candidate changed an earlier pronoun and contained a new place name. One more half-second candidate confirmed that the new clause persisted. The truncated quiet-tail recording had no full transcript reference and its longest screen interval was 1.548 / 1.556 s. [Three fixtures with acoustic activity, worker, source and screen times](extended.json)

The included window captures were taken during the original-speed runs. The final-worker checks exercised identical PCM at EOS, an additional 20 ms requiring a fresh decode, and an empty new segment. The paired CPU receipt preserves the original last-sample reading and the corrected maximum for each PID. Darwin can report zero accumulated CPU after a child has exited. Whole-process CPU and memory should be compared from the same input and repeated on both apps. [Actual worker EOS cases](worker-eos.json)

The identical 38.8 s public WAV also ran with both a native-window recorder and PID-scoped resource sampling. Chronological 442 runs used 18.30, 28.66 and 36.30 total CPU seconds; the two 459 runs used 18.83 and 34.82. Across the last adjacent pair, preview compute time was 26.411 and 26.510 seconds. The older build's longest window gaps were 3.102, 3.769 and 4.203 seconds; the new build's were 1.579 and 2.860 seconds. Thus a real long gap still occurs when execution is slower, and the data do not demonstrate a consistent CPU/footprint reduction. [Raw per-run costs and timing](../resource-comparison.json)

The independent accelerated cohort preserved all 440 final strings and recording-state sequences from build 442. The 420 unmodified originals have 910 edits over 10,663 reference units (8.534%). The 20 low-volume or noise derivatives have 65 edits over 764 units (8.508%). There are five existing unsuccessful subsegments across the original set, with no missing whole-file transcript. [Paired archive and state comparison](archive-comparison.json)
