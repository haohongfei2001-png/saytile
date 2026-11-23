# Saytile 0.22 — performance closure

2026-11-23 Asia/Shanghai. **Draft / HOLD. Two bounded allocation experiments; no optimization admitted.**

- Parent: PR #52 `codex/release-021`, refreshed head `5c3725b24eb1bb831758396548407faf5a057e5b`. Signed baseline: 0.21 (564), product source `06997bd613ac4dede54450702385259f3bc02f2c`.
- Independent branch: `codex/performance-022`. Installed 0.20 (533), main, PR #52, archives, keys and user model cache are untouched.
- Read parent STATUS, ACCEPTANCE, ARCHITECTURE, pressure pairs, failed publisher experiments and raw 3.368-second trace. Existing failures stay failures.
- Baseline native diagnostic replay: same 38.8-second public file, same load helper, 5.3333 observed cores. Both owned processes sampled successfully using macOS `sample` at 10 ms for 30 seconds. Final text 31/205 errors unchanged. Longest visible fresh-word gap 2.026 s in this diagnostic run, not a reproduction of the historical worst case.
- Full Xcode / Instruments / xctrace unavailable on this Mac. Capability evidence: `evidence/performance-022/diagnosis/environment.json`. `sample` is stack sampling, not a claimed Time Profiler or System Trace recording.
- Add opt-in bounded, text-free monotonic trace for fixture ingress, conversion, VAD, journal, ASR admission/pipe/output, preview decision, database commit and UI publication. Default product behavior and candidate admission remain unchanged.
- Next: build traced baseline, correlate stage timings, then test one allocation-related hypothesis supported by stack evidence. No decoder/publisher experiment enters product without paired native benefit and accuracy regression.

No microphone test (lid remains closed), API call, installation replacement, notarization, website/feed change, merge or public release is authorized in this task.

## Current experimental status

PR #53 holds the isolated follow-up. H1 has five attempted pairs, two valid; one valid pair regresses, one improves. Therefore H1 is NOT admitted. Invalid load runs are retained. H2 tests bounded reuse across preview calls without changing decoding. Its three pairs use a uniform 60-second quiet interval before each arm to reduce accumulated host contention; load validity and text scoring remain unchanged. No more allocation hypotheses or unbounded re-runs will be attempted.
