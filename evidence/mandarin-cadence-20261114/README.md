# Isolated automatic Mandarin cadence measurements

The installed 0.13 (414) candidate at cd41c60f0d7cb042c066c42147a58085b6f33f95 was replayed on this 24 GB MacBook Air M5. The app processed public recordings in fresh data directories at recorded speed, selected qwen-small automatically, and produced its actual AppKit timeline and final archive. Only the public fixture text and the window rendered from it are retained here.

* `baseline/panels` contains all 15 fixed public clips from `evidence/mandarin/panel-cohort.json`. `baseline/extended` contains the three longer regression cases from `evidence/mandarin-quality-20261114/delivery/extended/samples.json`. The quiet-tail truncation has no complete reference and receives no CER score.
* `baseline/panels.json` and `baseline/extended.json` score changes using `scripts/mandarin/score-live-cadence.py`. Time starts at input replay. Acoustic boundaries use the existing 16 kHz waveform onset/offset rule. Every new reference bigram counts once per clip for the main gap metric. A separate series preserves the older rule which compares against the preceding event. Mouse gestures, redraws and an animated reveal do not constitute ASR publications.
* The two `worker/stride-*.json` files use the very same signed helper (SHA-256 1fb6ae35c6b41143e0908d6cec4b12769059450c332411f52240b5426a9f06f9), model weights, 40 ms PCM writes and three public WAVs. Only the requested step changed, 19,200 vs 8,000 frames. Run `scripts/bench-local-asr.py --model qwen-small --paired evidence/mandarin-cadence-20261114/worker-cases.json` with the model directory, signed helper directory, public WAV directory, chunk seconds and output path. The helper stays resident across these three direct trials. The native panel tests start a fresh app per clip and additionally exercise VAD. Raw worker timestamps from separate trials cannot be subtracted from a native UI receipt.
* `baseline/continuous-resource/qwen-small.json` measures the isolated app and its helper on the 38.8-second public continuous fixture. The whole-machine watt reading includes other programs. The adjacent baseline contained concurrent CPU compilation and cannot isolate battery cost. Helper and app physical footprint are measured from their processes.


## Reading the comparisons

`preview-stride-only` is the intermediate signed 0.13 (440) run at 1c5525f0. The automatic 15-clip run first exercised the two longest stalls from (414); each clip had its own new process. This intentionally captures possible first-use cost. In the first such run the 7c8b sample's first decode took 1.857 seconds. The separate `first-reprobe` repeated the exact clip through another new process on the same host and measured 0.233 seconds. The original 1.857-second result stays in the distribution. The common probe timestamps identify a slower first inference without independently establishing its internal cause.

For the paired clip-level timing comparison, run `python3 scripts/mandarin/compare-live-cadence.py --manifest evidence/mandarin/panel-cohort.json --old BASE/panels --new NEW/panels --output paired-live.json`. Words are NFKC/case-folded using the original CER scorer. A scored item is two consecutive normalized reference characters first seen in the respective layer, deduplicated within a clip. A positive paired delta means the same text appeared earlier during actual replay. The clipping at the earlier EOF ensures both builds are scored while the recording is still arriving. Reference characters do not have word-level alignment, so this metric cannot measure the delay since a particular word was spoken.

The independent provisional-text diagnostic compares already visible text to its closest reference prefix by edit distance. Both builds are sampled on the same 100 ms playback grid from the later first visual output to the earlier EOF; repeated frames represent reading time. Across 1,056 paired instants the baseline displayed 20,946 normalized characters with 2,307 closest-prefix edits, and the new build displayed 22,729 with 2,402 edits. This is approximately 11.01% → 10.57% edits per *displayed* character in these frames. Optimizing the reference prefix ignores the unseen suffix and unknown word times. Full-utterance CER above remains the accuracy criterion.

`candidate` contains the signed 0.13 (442) receipts at d3b37a88. The 420 originals and 20 derived (quiet/noisy) clips exercise the production segmenter, journal, one Qwen worker and real SQLite archive. They are accelerated and are used only for accuracy. The 15 native replay clips, three longer files, resource runs and continuous-use soak are separately wall-paced. Each public fixture is verified by its manifest SHA-256. Public references include license and attribution in [the corpus record](../mandarin/SOURCES.md).


## Original-speed results on this host

| 15 public clips | 0.13 (414) installed baseline | 0.13 (440) cadence only | 0.13 (442) candidate |
|---|---:|---:|---:|
| Laid-out text first useful update P50 / P95, seconds | 1.184 / 2.055 | 0.966 / 2.743 | 0.974 / 1.608 |
| Source publication interval P50 / P95, seconds | 1.205 / 2.061 | 0.516 / 1.038 | 0.515 / 1.067 |
| Laid-out text interval P50 / P95, seconds | 1.135 / 1.361 | 0.515 / 1.045 | 0.514 / 1.039 |
| Gaps at least 2 seconds during acoustic activity range, source / screen | 7 / 7 | 3 / 2 | 0 / 0 |
| Longest screen gap, seconds | 2.990 | 2.743 | 1.850 |
| EOF to completed archive P50 / P95, seconds | 0.199 / 0.444 | 0.198 / 0.333 | 0.187 / 0.301 |
| Screen suffix replacements during the acoustic window | 8 | 25 | 26 |
| Normalized characters after the last unchanged prefix across those replacements | 39 | 97 | 97 |
| Archive CER, errors / normalized characters | 46 / 568 | 46 / 568 | 46 / 568 |

All three runs produced repeated meaningful updates in 15/15 clips. All 18 native final texts (including the three longer fixtures) are identical across the releases. The suffix metric counts the entire suffix after the first differing character, including retained words; it captures possible visible reflow. The higher number of interim revisions is a tradeoff of publishing more genuine model output.

The 38.8-second public fixture produced 31 → 56 reference-supported publications, with the longest gap falling from 2.465 to 1.520 seconds. On the 25.74-second fixture the longest remaining candidate gap was 2.043 seconds; only 41.2% of its 20ms audio windows exceeded −55 dB and its final half-second contained a real place-name revision. A 34.58-second quiet-tail fixture produced 25 → 49 literal updates. It has no full reference transcription.

On the complete accelerated comparison all 440 per-clip structured receipts are equal across builds, including text, recognition states and errors. The original 420 clips scored 910 edits / 10,663 reference characters. The twenty derived clips scored 65 / 764. Five existing subsegments remained failed within recordings which also contained a completed segment. All 440 full recordings produced text. In three files the incomplete segment was last (VAD spans 0.16/0.50/0.30 s) and the archived text had zero CER. The other two had incomplete leading segments (0.38/2.70 s, with 0%/0.7% of their 20ms blocks above −55 dB). Their full-wave direct and product transcriptions scored the same 4/28 errors respectively. Energy alone does not establish speech content. [Five source-paired cases](candidate/incomplete-segments.json) [Earlier segmentation evidence](../mandarin-quality-20261114/delivery/segment-status.json)

The same 38.8-second resource comparison measured old → new median app+helper CPU of 28.4% → 75.9% (100% is one CPU core) and peak simultaneous physical memory of 1,645.1 → 1,573.9 MiB. Average whole-system GPU power was 2.43 → 3.79 W. This Mac was on AC and background activity changed across runs. The old build was re-measured after the new build in `baseline/continuous-resource-repeat`, since the first baseline had concurrent compilation. Battery-only use and an 8 GB machine were not measured.

## 15-minute use

The same 905.020375-second input as the original 0.13 soak passed on build 442. All 47 recordings completed with a matching timeline row. The 79 readable audio chunks held 803.040375 seconds of journal audio on both builds. SQLite integrity was `ok` with zero foreign-key violations and no external dispatches. The helper was absent during the measured idle period and was present again on subsequent speech. Actual AppKit text changes on the same input rose from 579 to 911. This counter alone includes visual changes from one ASR result, so the independent source-publication evidence above is used to establish ASR progress.

Across the 15-minute session, app median CPU changed from 6.15% to 5.95% and helper median CPU from 12.3% to 31.3%. Helper peak RSS rose from 745.48 to 798.69 MiB. Candidate helper RSS medians in the first and last five minutes were 719.19 and 793.88 MiB. RSS from this longer run and the simultaneous physical footprint in the separate resource trial measure different resources. The earlier and later sampler windows cannot establish an indefinite memory bound. [Soak receipt](candidate/soak.json)
