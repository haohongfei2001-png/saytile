# Root-cause record

## Historical 3.368-second failure

Source: parent `evidence/release-021/cadence/raw/repeat-new-2`. Public WAV SHA-256 `5e7b5564803cec7cb90282b0427e99cd345472b758464060bf1f2ae5ba013c04`. Relative time uses `ProcessInfo.systemUptime - clockOriginUptime`.

Visible interval 23.065239–26.433493 s. Accepted model result at 23.044211, timeline at 23.055655, visible at 23.065239. Next raw results at 24.126082 and 25.327578 were withheld; accepted result 26.420455 reached timeline at 26.429079 and view at 26.433493.

Those three decodes took 1.0795, 1.1984 and 1.0920 s. An old phrase changes `视力` → `智利` → `这里`, with punctuation changes, while later words grow. The existing whole-prefix confirmation gate withholds two whole candidates. This is a combination of decode wall time and preview admission; it is not a 3-second SQLite/UI stall. Raw timing alone does not distinguish GPU work from host scheduling/allocator overhead.

The separate longest **timeline** interval (28.502–31.880 s) and raw-output interval (31.869–34.281 s) must not be conflated with the longest visible interval. Metrics retain the parent's scoring definition.

## Fresh baseline stack sampling

Files: `evidence/performance-022/diagnosis/baseline-profile/`, load receipt in adjacent `profile-load.json`. Instrumented diagnostic only; not one of the acceptance pairs.

- Actual 5.3333-core load; 40.400 s process wall time; combined CPU 12.71 s; peak simultaneous footprint 1683.3 MiB; 75 preview decodes, 15.430 s combined decode wall time.
- Main App main-thread stack: 2448/2536 samples in normal Mach event wait. No observed long main-thread busy loop.
- Worker main thread: 1425/2621 samples waiting for PCM, 1183 within Qwen transcription. Most transcription samples are in preview-token verification / MLX evaluation. Repeated Metal allocator, buffer creation and IOGPU residency-registration stacks are present.
- Upstream decoder synchronizes and clears its scratch cache after every call; host caps the allocator cache at 32 MiB. This is a plausible measurable allocation bottleneck, **not yet proven as a useful optimization**. No change to cache policy has been admitted.
- Sampling is wall-stack observation, not CPU-time attribution. Do not sum recursive counts or claim a GPU utilization/power percentage from these files.

Next isolate pipeline stages with monotonic trace, then test one bounded allocation policy against the same uninstrumented native baseline. No change to model weights, token semantics, publication gates, VAD, scoring or safety rules.

## Stage isolation and experiment H1

Traced baseline source `00387d91b376c4857af9768c98c842e846075474` with the unchanged signed baseline worker. 7547 timestamped events; raw trace and stage summary are in `diagnosis/stages-baseline`. Maximum observed conversion 0.145 ms, VAD 0.071 ms, journal append 3.257 ms, pipe write 2.884 ms, preview decision computation 3.877 ms, candidate persistence 1.273 ms, transcript persistence 2.549 ms, timeline read 1.171 ms. Seven raw hypotheses were withheld. Confirmation **waiting for another model output**, rather than the confirmation function's CPU execution, accounts for that gate's delay. Physical microphone not exercised.

H1 changes only Qwen-small allocator cache ceiling from 32 to 128 MiB. Sampling found 489 of 2621 worker-main-thread stack samples under allocator malloc; 368 under IOGPU resource-group registration (overlapping with those 489, not additive). Model weights, graph/math, token verification, preview admission, EOS, VAD and scoring stay unchanged. Upstream per-decode cache clearing remains. Hypothesis: less within-decode allocation churn reduces decode CPU and long preview wall time without retaining a larger pool during standby. Paired benefit, memory and exact final transcripts are mandatory before admission.

## H1 decision and bounded H2

H1 is NOT admitted. Five attempted pairs, only pairs 1 and 4 valid under unchanged per-load-worker 0.63–0.70-core rules. Their old/new longest gaps are 3.372/3.783 and 2.560/2.008 s; CPU 18.05/17.94 and 16.84/12.74 s. Final text is identical in all five attempted pairs. The new binary's first measured decode took 2.362 s; whether this was cold shader compilation or transient driver scheduling is UNKNOWN. Do not delete it or call it a publisher failure. Three invalid pairs retain all raw output. No third valid pair is claimed.

A second and final allocation hypothesis: keep the same 128 MiB ceiling but stop emptying spare buffers between verified previews, while clearing at final/first-pass/non-streaming decoding. The sampled repeated allocator and residency-registration paths motivate reuse across calls. Only spare allocations survive; the full audio-conditioned prompt, encoder and KV cache are recomputed exactly as before. H2 is compared to the original signed 564 with the same AB/BA/AB protocol; additional quiet time is recorded uniformly before every arm, not used to select successful results. No publisher or scoring change. If repeatable benefit is not established, revert both allocation experiments and deliver NO-GO.

The host is on battery. After the load series, Foundation thermalState=0 (nominal), lowPowerModeEnabled=false, activeProcessorCount=10; pmset reported no warning. These after-run observations do not establish the cause of earlier load misses. powermetrics is BLOCKED because it requires an interactive administrator password. No credentials or power/security settings changed.

## H2 final decision

Three of three AB/BA/AB pairs satisfy the unchanged load requirements. Full receipt: `evidence/performance-022/h2-summary.json`. Longest visible fresh-word gaps old/new: 2.026/2.063, 1.951/2.022, 1.997/1.994 s. CPU old/new: 13.67/15.50, 12.26/12.36, 12.40/13.24 s. First visible text old/new: 1.041/1.171, 0.993/1.101, 0.992/1.013 s. All pairs retain exactly the same final text (31/205 errors for this difficult continuous sample). One experimental arm adds an A→B→A reversal where its baseline has none.

H2 **NO-GO**. Faster allocation is not demonstrated; first text and CPU are worse in all three paired observations. Longest gap is worse in two pairs and only 3 ms better in one, below the view sampler resolution. Do not reinterpret this as benefit. The more regular pacing after the uniform quiet interval also occurs in the unchanged baseline; it is not attributable to the experiment. Both cache changes are reverted.

The allocation stacks are a real observed cost but were not established as a useful optimization lever. Full GPU execution vs host/driver scheduling attribution remains BLOCKED without Instruments/System Trace. Confirmation waiting is directly evidenced, but parent evidence already rejects unsafe publisher alternatives; this task does not admit an untested workaround. Final delivery is a signed diagnostic/regression candidate with baseline recognition behavior, **not a claimed responsiveness fix**.
