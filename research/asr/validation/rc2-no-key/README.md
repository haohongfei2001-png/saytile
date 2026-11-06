# RC2 no-key reliability closeout

2026-11-07. Baseline `45af67049ddee2553fe1929a812aecb83cc157e4`; PR4 stays open. No cloud requests, uploads, credentials, microphone or production data. Existing RC1 is preserved. Candidate.2 packaging and final artifact checks follow the runtime commit.

## Final integrated source

After the `a602236` checkpoint, independent review also repaired pending-erasure startup blocking, false absence on permission errors, stale recovery status, explicit-data-directory preference isolation, and candidate identity checks. `native-final.log`: **286 tests / 34 suites PASS**; `app-model-delivery.log`: **25 checks PASS**. The prior 283-test checkpoint below remains source-specific history, not the latest total. Storage follow-up and raw failures are in storage-review.md. The separate pipeline reviewer found no concrete P0/P1 in the erasure change; database/durability failures still propagate.

Past ordinary held processes with only --data-directory had isolated databases but could use standard preferences. This limitation is now corrected at launch; prior receipts are not retroactively treated as proof of preference isolation. Final package tests follow the clean runtime commit.

## Earlier integrated checkpoint

- `native-all.log`: 283 tests / 34 suites passed, final frozen source including the 1-second test watchdog and tap sample-rate guard.
- `app-model-final.log`: 25 checks passed on the same integrated source. Burst refresh actually performs 2 database passes for 40 requests; original failure was 40.
- [Storage review](storage-review.md): atomic failure state, retryable audio recovery, read-only WAV, per-record inaccessible directory isolation; real filesystem permissions and SQLite failures.
- [Pipeline review](pipeline-review.md): finalization cancellation and draining independent reviews; raw audio, stable text and candidates protected.
- [Lifecycle review](lifecycle-review.md): permission-await decisions, PCM-paced replay, callback layout/clock guards; includes the 120-second wall-clock synthetic capture and exact pre-rate-guard source snapshot.
- [AppModel review](app-model-review.md): shared refresh versioning and closed-store boundary.

Focused counts overlap the full suite and must not be added. Logs named before/red contain actual failures, not hypothetical examples. The two build-overlap logs stopped before test/resource execution and remain separate. No tests weaken evidence validation or replace original candidate safety assertions.

## Limits

Synthetic transport results do not prove real Qwen/AssemblyAI/Astra/Gemini/Scribe connections, speech accuracy or fusion gains. System permission inputs and injected format changes do not prove physical lock/sleep/device events. Short process resource observations do not prove 72-hour stability or whole-system energy. Existing unconfirmed background WebKit insertion and ad-hoc signing limitations remain. No additional user action is requested for this no-key round.
