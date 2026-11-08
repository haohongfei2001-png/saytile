# Saytile upstream integration — 2026-11-07

- Docs / PR5 merge SHA: `2018c0b02abc20b9575868e32cc2f81c03d833ac`.
- Engine / PR6 implementation merge SHA: `fffbefa4381412bcefc7555ac5f395c39e859623`. This report is a subsequent documentation-only commit on the same branch.
- Preserved upstream PR4: `a602236ea48f7140b57c46e916bae4c5d43f5cd9`. Verified ancestor of both merges; PR6 also retains initial `c4c74e6`. No cherry-pick or replacement of ancestry.

Preserved PR4 atomic/retryable storage recovery, inaccessible-record isolation, tap/lifecycle guards, saved-audio pacing and coalesced AppModel refresh. Ported independent review ownership into SingleTranscriptEngine: cancellation retains/drains the review task, closes the persistent GPT transport before waiting, and owns EOS finalization under the same cancellation handler/watchdog. Old session actor was not restored.

Product contract retained: two equal whole-audio experts, exactly one GPT-6 core and persistent WS, one consumer transcript; Apple Candidate ingress/cloud outage fallback; exact owned external range repair with user-edit/target-change protection. No model/reasoning substitutions or secondary reviewer defaults. Existing PR4 regressions were preserved; acoustic-review expectations explicitly reconciled to GPT selecting genuine ASR evidence.

Validation: **325 Swift tests / 39 suites: 321 passed, 4 environment-blocked; exit 1. AppModel: 25/25 passed; exit 0.** The four blocked tests are two synthetic Keychain operations (`.keychain(100001)`) and two silent playback operations (`无法播放原音`). Tests were not skipped or weakened. Review cancellation/EOS/watchdog, persistent GPT, recovery, failover and owned-range correction suites passed. AppModel used isolated scratch and synthetic data; 40 refresh callers required 2 database passes.

[Commands, exact blocked test names, raw logs and 154 source/test hashes](research/architecture/validation/upstream-final/README.md). Scratch: `/tmp/saytile-upstream-final`; only the existing test scripts were used, sequentially sharing that build cache.

Unresolved boundaries: real cloud accuracy/API connectivity, microphone/device lifecycle, real external application repair, install/upgrade and release acceptance were NOT_RUN. Keychain/playback require acceptance outside this restricted test environment. No CI polling, push, release, paid API/audio upload, installed-app/production-data/preferences/permissions/key changes. Only docs-repo and upstream-repo were modified; integration-repo and main were untouched. Parent handles push and further integration.
