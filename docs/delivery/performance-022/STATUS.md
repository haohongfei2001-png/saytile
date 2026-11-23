# Saytile 0.22 — performance closure

2026-11-23 Asia/Shanghai. **Performance NO-GO / Draft / HOLD. No optimization admitted.**

- Parent: PR #52 `codex/release-021`, refreshed head `5c3725b24eb1bb831758396548407faf5a057e5b`. Signed baseline: 0.21 (564), product source `06997bd613ac4dede54450702385259f3bc02f2c`.
- Isolated follow-up: PR #53, `codex/performance-022`. Installed 0.20 (533), main, parent code, personal archives, keys and model cache are protected.
- Historical 3.368 s visible gap is decode time plus whole-candidate confirmation waiting, not a multi-second database/UI stall. Full correlated baseline trace and owned-process stack samples are retained. Instruments/System Trace unavailable without full Xcode; power counters require interactive administrator privilege. Neither is claimed as passed.
- H1: five attempted pairs, two valid, inconsistent results; rejected.
- H2: three of three pairs valid at 5.3158–5.3350 load cores. Longest visible fresh-word gaps old/new: 2.026/2.063, 1.951/2.022, 1.997/1.994 s. CPU old/new: 13.67/15.50, 12.26/12.36, 12.40/13.24 s. Final text identical in all pairs, but no repeatable latency or CPU benefit; rejected.
- Both allocation changes reverted to exact baseline worker source/patch. No publisher, scoring, VAD, model, or safety constraint changed. Evidence and failed experiment commits are preserved. No further allocation experiments planned.
- Opt-in bounded, text-free monotonic fixture tracing remains. Review removed an unsafe diagnostic integer conversion before the existing candidate validator; a regression verifies malformed timestamps cannot crash, discard original audio, or overwrite a user edit. Trace timestamps are serialized with append order.
- Final product source **a90601b79e59333c97982e200dfb69e541c2bf95**, 0.22 (567): signed native candidate, 15 real-time public replays (46/568 CER), 420 original public clips (910/10663 CER), plus 20 derivatives; all 440 final texts/states unchanged. Normal speed benefit/non-regression is not established (first-word P95 1.499 → 1.568 s vs prior receipt).
- Full final-source CI: 569 Swift Testing + 30 XCTest, zero failures; 220 AppModel checks; isolated native UI and AppKit/WKWebView/TextEdit/Chrome/Edge/Safari input checks pass. Native run 45124247723. Physical sleep capability is explicitly BLOCKED, not promoted by the green job.
- Final-source local storage: 18 actual SIGKILL/write-failure/recovery checks pass. Synthetic 533 → 567 → 533 → 567 upgrade/rollback preserves recordings, manual edits, drafts, audio and uncertain dispatch. Installed 533 executable hash remains unchanged.
- Final DMG 64,535,471 bytes, SHA-256 **b81fa67571c956186734063be1e555223e7814dfd32d3fa54049ce829438de94**. Developer ID/signature/readonly mount/isolated startup pass. App and DMG Gatekeeper both reject Unnotarized Developer ID; notarization explicitly NOT_RUN.
- Closure: [acceptance](ACCEPTANCE.md), [architecture](ARCHITECTURE.md), [candidate instructions](INSTALL.md), raw evidence `evidence/performance-022/final/`. No performance fix admitted; **NO-GO / HOLD** remains the final decision.

No physical microphone test (lid remains closed), paid API, installation replacement, notarization, website/feed change, merge or public release.
