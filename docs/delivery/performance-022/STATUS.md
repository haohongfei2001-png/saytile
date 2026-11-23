# Saytile 0.22 — performance closure

2026-11-23 Asia/Shanghai. **Performance NO-GO / Draft / HOLD. No optimization admitted.**

- Parent: PR #52 `codex/release-021`, refreshed head `5c3725b24eb1bb831758396548407faf5a057e5b`. Signed baseline: 0.21 (564), product source `06997bd613ac4dede54450702385259f3bc02f2c`.
- Isolated follow-up: PR #53, `codex/performance-022`. Installed 0.20 (533), main, parent code, personal archives, keys and model cache are protected.
- Historical 3.368 s visible gap is decode time plus whole-candidate confirmation waiting, not a multi-second database/UI stall. Full correlated baseline trace and owned-process stack samples are retained. Instruments/System Trace unavailable without full Xcode; power counters require interactive administrator privilege. Neither is claimed as passed.
- H1: five attempted pairs, two valid, inconsistent results; rejected.
- H2: three of three pairs valid at 5.3158–5.3350 load cores. Longest visible fresh-word gaps old/new: 2.026/2.063, 1.951/2.022, 1.997/1.994 s. CPU old/new: 13.67/15.50, 12.26/12.36, 12.40/13.24 s. Final text identical in all pairs, but no repeatable latency or CPU benefit; rejected.
- Both allocation changes reverted to exact baseline worker source/patch. No publisher, scoring, VAD, model, or safety constraint changed. Evidence and failed experiment commits are preserved. No further allocation experiments planned.
- Opt-in bounded, text-free monotonic fixture tracing remains. Review removed an unsafe diagnostic integer conversion before the existing candidate validator; a regression verifies malformed timestamps cannot crash, discard original audio, or overwrite a user edit. Trace timestamps are serialized with append order.
- Next: bind final native/regression evidence and signed diagnostic candidate 0.22 (567) to the frozen source; retain NO-GO irrespective of CI success.

No physical microphone test (lid remains closed), paid API, installation replacement, notarization, website/feed change, merge or public release.
