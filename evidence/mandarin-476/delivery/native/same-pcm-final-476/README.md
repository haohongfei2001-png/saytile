# Build 476: same-PCM checked preview versus independent scalar EOS

Source: `0fbca1d892bbc8aa550c4439b8cfcb045af825ae`, build 476. The actual signed helper SHA-256 is `9b21b863a3b5bad11d4d36ee33b8204c0648da9409a977fd64d1c756cea2340e`; the script verifies the entire app signature and embedded source before spawning the helper. One persistent worker, one active model, no microphone, no network or private audio, no native app launch. Complete execution took 60.190 seconds and worker exit was 0.

## Result

- PASS: all 17 original PCM endpoints were paired with an observable exact-endpoint preview decode and a subsequently recomputed scalar EOS decode at the identical frame count. No case was dropped, padded, or declared successful after a missing event.
- PASS: all 17 normalized character sequences match; 15/17 full strings match. The 16 complete-source references score identically: 51 errors / 660 units (7.7273% CER). The 30.0-second excerpt of a 38.8-second concatenation has no independent full reference and is excluded from CER.
- 14/17 endpoints accepted checked draft tokens; 12/14 of these are exact string matches. The other 3 endpoints accepted zero prefix tokens and are separately classified, not counted as acceleration evidence.
- The two string differences contain only punctuation: `ascend-mixed-ee4e2d5087648134` gains a comma after the first two characters at scalar EOS; `continuous-public-5` changes a dash and one sentence-ending period to commas. There are no lexical substitutions, insertions, or deletions between the paired hypotheses under the unchanged repository normalization.
- Across the 14 endpoints with accepted prefix tokens, measured decode wall time totals 7.445 seconds for checked preview and 9.689 seconds for scalar EOS. Individual previews are not uniformly faster. These are direct-worker decode times, not native-window or first-character latency.

The sample supports retaining the current checked-preview path, but does **not** establish that scalar EOS may be removed safely for all future speech. Build 476 retains independent scalar finalization. This experiment made no product change.

## Method and boundaries

`compare-same-pcm-final.py` uses the same public 15 short clips, the full 25.74-second FLEURS long clip, and exactly the first 480,000 frames (30 seconds) of the 38.8-second public concatenation. `result.json` binds each original WAV and consumed PCM to SHA-256, gives the actual prefixes, exact frame counts, model revision, every worker event, each decode timing, text hashes, and text differences.

At least one fresh 8,000-frame stride separates the final input endpoints; no silence or invented PCM is inserted. All intermediate data is sent in packets no larger than one second. The script waits only a bounded interval for each preview, then sends the normal zero-length EOS. It neither modifies the protocol nor coerces duplicate previews to emit. Six unchanged endpoint results are recovered only when the exact endpoint decode explicitly records `changed=false`, proving that the previous emitted hypothesis is still its exact text; all other compared endpoint texts were actually emitted at that exact frame. Every compared scalar EOS contains its own later final decode with zero accepted prefix tokens.

This is deliberately an accelerated direct-worker experiment, not an original-rate app run. A coalesced endpoint or missing scalar decode would be `NOT_COMPARABLE`; none occurred. Full references are scored by the existing `scripts/score-local-asr.py`, preserving its NFKC/case-fold/punctuation normalization without lexical corrections. Hashes below bind the raw receipts and scripts.

## Reproduction

Run the included comparison script from the product repository, supplying these explicit inputs: `--app` signed build 476, `--weights` the pinned weights parent, `--paired` the prior `panels-first-worst.json`, `--audio` its verified WAV directory, `--extended-manifest evidence/mandarin-quality-20261114/delivery/extended/samples.json`, `--extended-audio` its public WAV directory, `--model-manifest Sources/SaytileKit/Resources/LocalASR/qwen-small.json`, `--scorer scripts/score-local-asr.py`, `--sha 0fbca1d892bbc8aa550c4439b8cfcb045af825ae`, and a fresh `--out` path. Default maximum run time is 120 seconds. `--prepare-only` performs input/identity checks without launching a model. Recompute the summary with `python3 summarize.py result.json`.
