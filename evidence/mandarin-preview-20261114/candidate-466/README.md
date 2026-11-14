# Final M5 product-path verification for build 466

This directory is tied to the signed 0.13 app built from ff8f8a014bd6b554a5703971a1139d94da155a6c. The native runs fed frozen public WAVs at wall-clock speed through the app's automatic Qwen 0.6B route, PCM/VAD, transcript engine, isolated SQLite and AppKit window. All 15 short and three extended recordings match the older build's archive character for character. No microphone input is used in these runs.

| 15 original-speed samples | 442 | 466 |
| --- | ---: | ---: |
| Final CER (errors / 568 characters) | 46 / 568 | 46 / 568 |
| First meaningful window text P50 / P95, s | 0.923 / 1.51 | 0.976 / 1.511 |
| Meaningful source interval P50 / P95, s | 0.513 / 1.115 | 0.515 / 1.034 |
| Meaningful native text interval P50 / P95, s | 0.514 / 1.040 | 0.437 / 1.011 |
| EOF to archive completion P50 / P95, s | 0.218 / 0.694 | 0.206 / 0.353 |
| Screen revisions, punctuation included | 151 | 59 |
| Withdrawals of premature sentence-ending punctuation | 106 | 9 |
| Lexical revisions / actually deleted or replaced characters | 26 / 40 | 27 / 41 |
| Sampled preview errors per displayed character | 0.10625 | 0.10667 |

The 25.74 s natural recording, 38.8 s concatenated speech and 34.58 s clipped quiet-tail fixture had longest visible gaps of 1.569, 1.592 and 1.893 s. On 442 these were 2.080, 4.883 and 1.548 s. The two complete-reference files had the same 5 errors in 92 characters and 31 in 205. The last fixture does not have a complete independent reference. Corrected provisional punctuation and the long-clause freeze are clearly visible in the same native window; a general gain in final Mandarin accuracy is not established. [All three public fixtures](extended.json)

The prior experimental worker schedule had a repeatable failure mode on the 25.74 s recording. One 461 run held the screen for 8.390 s despite 13 intervening real model updates. The actual failing sequence was saved and exercised against the selected publication policy separately. This native build returns to the previously accepted worker cadence. [Time-aligned raw replay](../two-correction-replay.json)

A separate adjacent 38.8-second old/new native replay sampled both processes. The source was delivered on the same clock while observing app and child with the same scripts. Build 442 used 18.71 CPU-seconds and build 466 used 19.42. Workers spent 22.012 and 22.218 seconds on 73 preview decodes apiece. Combined peak physical footprints were 1,829.3 and 1,818.0 MiB. The longest visible gap fell from 2.869 to 1.551 seconds, with native interval P95 of 1.546 and 1.110. A separate 466 run, overlapping independent compilation, reached 2.196 seconds. The data support reduced display freezes without establishing a CPU, energy, or RAM saving. [CPU and actual window timing](cpu-pairs.json)

The full product archive path on this exact revision was also tested at accelerated speed across 420 originals plus 20 derived quiet/noisy copies. All 440 final transcripts and per-recording state lists match the previous build. The separate cohorts gave 910 errors / 10,663 reference characters (8.534%) and 65 / 764 (8.508%). All clips yielded a nonempty archive. Five pre-existing incomplete subsegments are visible on the 420 originals. [Every final archive matched](archive-comparison.json)
