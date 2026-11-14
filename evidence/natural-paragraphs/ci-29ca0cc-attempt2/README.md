# 481 final source, controlled attempt 2 — FAIL retained

Source `29ca0cc323fcdf4f1ed53ca98b546b11e98f9f31`. This was the sole authorized `--failed --debug` rerun of the native job after the same source's local localhost reproduction passed 13 tests / 52 cases / zero protocol violations. **No further rerun was performed.** First failure remains untouched in `/private/tmp/saytile-natural-ci-final/`.

## What changed in this observation

The previous failing localhost wizard normal case **passed**. All four wizard cases passed (normal, unsupported, churn, each_reconnect), totaling 43.341 seconds; the entire protocol suite passed 13 tests in 56.380 seconds. Exact normal-case duration is not in the buffered log. The workflow did not retain raw wire/server artifacts; debug does not add them.

The native job then failed in **`AudioPlaybackTests.swift:144`**, `paragraphKeepsIdentitySeeksAcrossRecordingsAndSkipsMissingOriginals`, at `playbackPosition >= 0.9 && playbackPosition < 1.5`. The lower bound was false; the test logger did not print the actual Double. Second-recording identity and all other assertions passed. Test wall time was 8.522 seconds amid 494 concurrent tests, while the synthetic paragraph lasts 1.6 seconds. A possible sample-quantized player time or scheduling issue must be confirmed rather than assumed. Preserve the exact failure and investigate actual seek readback; no arbitrary tolerance or skip.

## Complete count

**523 Swift tests executed: 522 passed, 1 failed, 1 issue.** Groups: 4 PASS + 13 PASS + 12 PASS + 494 (493 PASS / 1 FAIL). AppModel and later native UI/timeline/boundary/startup/package steps were **NOT_RUN** after that step failed. Do not label the same-SHA CI green.

Overall checks remain **4/5 successful**. Cloud and contracts were not rerun. GitHub assigned the carried-forward foreground result a new job ID, but its original timestamps and identical log SHA prove it was not executed again. Foreground safety passed on disposable targets; hardware sleep remains **BLOCKED** on the VM. Existing foreground/power artifact IDs were reused, not downloaded again. Parent's local native/rollback evidence remains separate.

`receipt.json` contains job IDs, actual scopes and skipped steps. Full debug native log, failure excerpts, local reproduction hashes and artifact ZIP checksums are retained. No product source, installed app, microphone or private data was touched by this monitor.
