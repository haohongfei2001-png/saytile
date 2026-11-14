# PR #40 fixed-source GitHub CI acceptance

- Product source: `7fd9296d8eb2bd81379bbaa7287844d0d46703d5`.
- PR: https://github.com/haohongfei2001-png/saytile/pull/40
- Native run: https://github.com/haohongfei2001-png/saytile/actions/runs/43559075106
- Cloud run: https://github.com/haohongfei2001-png/saytile/actions/runs/43559075053
- Design run: https://github.com/haohongfei2001-png/saytile/actions/runs/43559075142
- Result: **5 jobs succeeded, 0 failed**. No rerun or source change was performed by this reviewer.

## Automated tests

- Swift Testing: **504 executed / 504 passed / 0 failed / 0 skipped**. The four disjoint invocations report 4, 13, 12 and 475 tests. Timing-sensitive suites run serially first and are excluded only from the final invocation, so coverage is not omitted.
- AppModel: **167 checks passed**, with isolated data and no microphone or external input.
- Native boundary: **20 PASS / 0 FAIL / 1 NOT_RUN**. Real macOS Accessibility/WindowServer on disposable own windows tested displacement, restoration, manual placement ownership, cancellation, refusal, idempotence, hidden states, target ambiguity, the real controller and AX events. The six actual compiled source files match the fixed Git objects by SHA-256.
- Foreground: owned AppKit, WKWebView, TextEdit disposable document and Chrome disposable profile succeeded. First insertion, append, deduplication, Unicode selection/prefix/suffix protection, manual edits, target changes and cancellation were exercised. Receipts show zero sends/submits; uncertain or unobservable writes were refused without automatic replay.
- Inline editor: actual typing, copy/paste with a private clipboard, deletion, Chinese IME, newlines and archive history passed; reopening preserved revisions and deliberate deletion.
- Native timeline: 12,003 rows, 64 resident, wheel-to-paint 0.1144 s, idle movement 0 pt, page anchor delta 1 pt. Selection and isolated archive checks passed.
- Native rendering: 30 standard and 3 reference captures passed. Rendering itself is not subjective visual approval or a complete remote-control interaction test.
- Bundle build and isolated startup passed. CLI isolation reports 18 cases; connection setup reports 7 cases.
- Cloud: isolated Postgres/Supabase/private account/Keychain/local ASR+GPT protocol peers passed. This does not establish a real paid service connection.

## Explicit limitations

- **BLOCKED** — real system sleep/wake on the hosted `VirtualMac2,1`: system sleep request exited 71, zero actual kernel sleep/wake events. The workflow step records this limitation and succeeds; it is not a hardware sleep PASS.
- **NOT_RUN in CI** — real fullscreen boundary: the explicit fullscreen fixture option was not enabled. Separate local same-source acceptance has 28/28 PASS including an actual fullscreen window, production controller movement and restoration.
- **NOT_RUN** — remote AX controls in the screenshot rendering job: helper absent. The separate native gesture/editor/foreground/boundary interaction receipts remain valid.
- **NOT_RUN** — this monitoring task did not test a user's microphone, real natural speech, or paid cloud providers.
- The boundary receipt preserves an AppKit platform observation with `expected_unchanged_frame_status: FAIL`: the early premise that declared `minSize` forbids all frame changes was disproven. The observed frame satisfies the declared minimum, and the worker records partial geometry/refusal. This is not one of the 20 passing product assertions; the separate actual AX-resize-refusal fixture passed.

## Evidence and copying

`receipt.json`, `check-runs-final.json`, `run-*-final.json`, `artifacts-final.json`, `boundary-artifact-verification.json`, all five complete `*.log` files, `panel-boundary-artifact/report.json`, `panel-boundary-artifact/source-binding.json`, `panel-boundary-artifact/probe.log`, and `power-artifact/power.json` / `power-events.jsonl` are suitable to retain as this CI receipt. The full logs use disposable hosted runner paths and isolated test text.

Do not copy `panel-boundary-artifact/frontmost.json`; its transient host process identity is not needed. No local user data, recordings, application cache, or credentials were read or collected. The candidate application artifact was not downloaded or installed by this reviewer.

The downloaded boundary archive SHA-256 is `e9b7722d29b3b84a8575ef283112946207e174f3639e77b8ff24834f3f9fba27`; foreground archive `cf8b8c27ca00040c43e92fee0d1dac203ff2c5dc46dc8fabebedf54c557f21a6`; sleep archive `89425c1472d02d9917e2c0c26ae63341821e90b2a43d80d4173fa7ae76200614`. Each equals the GitHub artifact digest.
