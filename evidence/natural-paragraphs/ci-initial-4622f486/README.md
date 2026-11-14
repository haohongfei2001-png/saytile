# PR #41 initial final-source CI — retained failure

Source: `4622f486987f920e4ec725eb20934561ea6c9a7f`, 0.15 (480). All three runs completed; **4/5 jobs succeeded, native failed**. This is a historical failed run and must not be relabelled as green by a later correction. No CI retry or installation was performed by this monitor.

- Swift Testing: **523/523 passed, 0 failed**, four separately reported groups: 4 + 13 + 12 + 494.
- AppModel: **172 checks passed**.
- Foreground: isolated AppKit, WKWebView, TextEdit and Chrome passed insertion, append, ownership and zero-send checks.
- New natural paragraphs: **16 checks passed** with 4 synthetic originals, 3 paragraphs and 2 time groups; silent WAV playback used AVAudioPlayer. Star/play were model actions; real pointer control actions were **NOT_RUN**.
- Window boundary: **20 checks passed**, CI native fullscreen **NOT_RUN**. The earlier minimum-size platform observation remains as explicitly historical failed evidence.
- Hardware sleep/wake: **BLOCKED** on VirtualMac2,1; not counted as a hardware pass.
- General UI: 33 native render screenshots; interactive controls **NOT_RUN**.

## Exact failure

At 2026-11-14T06:28:07Z, the step `Native continuous timeline with 12000 isolated utterances` emitted:

```
UI_REVIEW_FAILED midnight interrupted continuous Chinese text
```

The frozen `UIReview.swift` assertion requires the previous span to end exactly at the next span location across a day boundary (no separator). The fixture in `scripts/test-native-timeline.py` inserts records 24 seconds apart and adds 200 seconds every four records. The actual midnight pair is 224 seconds apart. Thus every relevant adjacent recording exceeds the newly intentional 15-second natural-paragraph threshold. Exactly one paragraph newline is expected. The source excerpts in this directory bind this diagnosis to the failing SHA.

Only this obsolete test assertion should change: require empty time markers, real cross-date identity, distinct natural paragraphs, exactly one newline, and unchanged text/order. Do not change production timing, grouping, rendering or scoring. Parent is coordinating that isolated test correction and a new SHA/CI; this directory remains the original failure.

Before this assertion, 12,003 rows / 64 resident, zero idle shift, one-point paging anchor, zero horizontal/shear shift and 0.038408291-second wheel-to-paint passed. Later timeline, startup and packaging steps skipped by CI are **NOT_RUN**; do not infer success.

`receipt.json` lists all job URLs, failed/skipped steps, counts and scope. Full logs and GitHub JSON are retained. Artifact ZIPs were verified against GitHub-advertised SHA-256; selected machine evidence was extracted, excluding frontmost metadata. General UI screenshot ZIP is not downloaded, as full job log already captures the exact failure. `SHA256SUMS.txt` binds all included evidence.
