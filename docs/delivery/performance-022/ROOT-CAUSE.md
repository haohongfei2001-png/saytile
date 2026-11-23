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
