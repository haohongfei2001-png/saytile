# RC2 no-key reliability closeout

2026-11-07. Baseline `45af67049ddee2553fe1929a812aecb83cc157e4`; PR4 stays open. No cloud requests, uploads, credentials, microphone or production data. Existing RC1 is preserved. Clean candidate.2 runtime `7320228955cec7bb4d24ff19700f37d1ef0ddbc3` is now packaged and checked; see delivery-manifest.json.

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

## Final package evidence

- [Exact identity and limits](delivery-manifest.json): source 7320228, clean release App extracted from readonly DMG, strict signatures, RC1 preserved. Old candidate.1 App moved to dist/Saytile-rc2-candidate.1.app; its DMG remains unchanged.
- [Actual native interface review](native-ui-review.md), ui-final-manifest.json and ui-final.log: 15 views / 6 control groups, no activation or outside foreground transition observed.
- connection-setup-cli-final.json: 7 actual command boundaries; cloud-probe-cli-final.json plus cloud-probe-cli-artifact.json: 4 actual command boundaries, 0 provider calls.
- install-upgrade-final.json/.log: 8 actual released RC1 DMG upgrade/restart/refusal/explicit-copy rollback checks. Candidate source/version/binary pinned; held process confirms isolated preferences.
- app-idle-final.json/.log: 120.042-second final packaged process, 1.07 user + 0.21 system CPU seconds, maximum RSS 105725952 bytes, zero swaps. Warm sampled RSS 73904–102416 KiB, last 93168 KiB. No microphone/ASR; not whole-machine energy or long-term stability.
- [Package isolation review and exact reproduction commands](package-isolation-review.md): prior preference-isolation limitation corrected; six development checks are separate from final package evidence.

Cloud connections, quality gains, confirmation latency, physical device/permission behavior and background WebKit write success remain unverified. No user action is requested.

Exact runtime macOS CI and design contracts both passed: [native 42287027227](https://github.com/haohongfei2001-png/saytile/actions/runs/42287027227), [contracts 42287027237](https://github.com/haohongfei2001-png/saytile/actions/runs/42287027237). `runtime-ci.json` retains verified Swift 6.3.3 log excerpts and artifact identity. The CI artifact and local DMG are separate binaries/build environments. Final evidence-only head checks are tracked on PR4 without repeatedly rebuilding this runtime.
