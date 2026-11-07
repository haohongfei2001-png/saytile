# Background fixture isolation and target-change regression

Scope: test fixtures and runners only. Saytile production input, audio, Store and authorization logic were not relaxed or changed by this work. These are preliminary validations before the next frozen runtime, not a replacement final delivery run.

## Preserved findings

The original a6849128 ordinary AX run failed its first strict confirmation assertion. A separate bounded diagnostic recorded exactly one production setter, then a later target caret change from 11 to 12; the production coordinator correctly invalidated its binding and stored `unverified`, with no owned range and no replay. The original failing probe did not print its result and automatically removed its isolated Store, so its exact cause cannot be reconstructed from later runs.

One independent diagnostic target also contained nonfixture characters before binding. Their source remains unknown. Two diagnostic text-witness fields in the submitted evidence were replaced with UTF-16 lengths, SHA-256 digests and fixed-fixture equality=false; original raw bytes remain local outside Git. Application activation observations alone do not prove keyboard isolation. Automatic text processing was enabled in the inspected diagnostic control, but no evidence establishes it as the cause of either anomaly.

## Fix

- Default native, WebKit and owned-range panels cannot become key or main, are transparent and ignore mouse events. Keyboard events are counted and discarded without inspecting characters. The opt-in foreground fixtures remain unable to receive keyboard input until their existing guarded `activate` command succeeds.
- Native insertion controls explicitly disable automatic rewriting. Startup requires the exact synthetic value/range and a non-key/non-main window; final/IPC receipts require zero keyboard events. Unknown values are omitted from fixture output.
- All original nine strict native insertion checks remain. Five additional checks use the real production AX setter, followed by a separately counted target-side AX insertion, to prove `unverified`, invalidated binding, one durable dispatch, no owned range and no repeat.
- Failure stores are retained by the revised ordinary probe. Existing WKWebView insertion stays explicitly unverified when the setter is acknowledged but the DOM is unchanged.

## Validation

`final/input-native-coordinator.log`: native9 + deterministic target-change5 PASS after transparent/mouse isolation. `input-webkit-observer.log`: six observer checks + two capability rejections, zero sends, with key/main=false and zero keyboard events. One outside foreground transition was observed during WebKit; owned processes never activated and no cause is inferred.

The first isolated owned-range run passed six scenarios then failed `focus-change`: its injected target selector stayed on the old field while a non-key window changed its first responder without a guaranteed AX focus notification. The retained failure is `owned-range/pre-focus-adaptation-summary.json`. The revised focus case uses nonce/PID/AX-identifier-checked reporting of the actual owned window first responder to update the existing target-selection seam. It proves final snapshot rejection after that real responder change, **not** delivery of background or production foreground AX focus notifications. No coordinator invalidation/notification is fabricated.

Final revised owned-range9 verification: **PASS**, all nine scenarios; `final/owned-range-summary.json` binds the executed binaries and confirms no source changes during the run. All owned fixture processes were cleaned up. Production foreground resolver, application TCC identity and third-party browser insertion remain outside this fixture scope; historical UNKNOWN/unverified evidence is retained.
