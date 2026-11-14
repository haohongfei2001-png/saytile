# PR #41 / 481 — first CI attempt retained as FAIL

Source `29ca0cc323fcdf4f1ed53ca98b546b11e98f9f31`. Four of five jobs passed. Native stopped in `Real localhost provider protocols (no API keys)` at 06:42:28 UTC. No retries or source modifications were made by this monitor.

## Exact evidence

`actualConnectionWizardBackendUsesBoundedProductionNetwork(fault: "normal")` failed only its pipeline-complete and both-services-verified assertions (lines 304 and 305). The 12-second watchdog cancelled it after 12.0248 seconds. Qwen's last persisted sequence was 3; GPT performed one received live review, but no EOS completion occurred. The same test's subsequent loopback peer snapshot verified full PCM byte count/hash, one Qwen connection, EOS=true and no protocol violations. These are passed-assertion inferences: the raw wire audit and server log were not uploaded by this workflow. Later unsupported/churn/each_reconnect cases and both production-session cases passed, so the peer server remained alive/reachable.

All eight protocol-related source files in `protocol-source-binding.json` are byte-identical to the prior source's passing protocol run and to the 0.14 baseline. The change from 480 to 481 only corrects the native UI review's midnight assertion plus documents it. The observed failure is an undetermined client drain/scheduling stall; current evidence does not prove deterministic product failure or harmless CI environmental flakiness. Do not extend the deadline, skip the assertions or silently rerun.

## Counts and scope

- Swift Testing actually run: **17**; **16 passed, 1 failed**, 2 issues. Remaining **506 NOT_RUN**. Do not carry forward the prior 523/523 total as this run's result.
- AppModel, natural paragraphs, panel boundary, 12k timeline, general UI, startup and package checks: **NOT_RUN** after earlier failure.
- Foreground: **PASS** on isolated AppKit/WKWebView, TextEdit and Chrome, including zero automatic send. Batch summary: 10 cases, 0 failures.
- Hardware sleep/wake: **BLOCKED** by hosted VM capability, not hardware acceptance.
- Parent separately holds same-SHA local 12k/AX-copy and rollback PASS evidence; it must be cited separately, not substituted for these skipped CI steps.

`receipt.json` includes job URLs and skipped steps. `failure-excerpts.log`, full native log, source binding and extracted foreground/power artifacts retain the actual observations. ZIP digests match GitHub's advertised SHA-256. `SHA256SUMS.txt` binds the receipt. Previous 480 failure remains untouched at `/private/tmp/saytile-natural-ci/`.
