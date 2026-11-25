# 577 native CI: independent evidence review

Tested product source: `3e1cc6961df4da01a1c52310755a7dd215ef4310`, 1.0.1 (577).
[Native workflow 45576254680, attempt 1](https://github.com/haohongfei2001-png/saytile/actions/runs/45576254680): all three jobs succeeded. This collection only downloads and reads existing results; it does not rerun tests or alter product code.

## Test counts

- **Swift Testing: 584 total / 584 passed / 0 failed.** Seven disjoint batches: 4 + 13 + 12 + 1 + 9 + 8 + 537. The 584 individual test starts and passes agree with runner summaries. The 265 parameter-case starts are not the test total.
- **XCTest: 30 total / 30 passed / 0 failed.** Counted individual case passes and checked the package summary. The identical parent `Selected tests` total is not counted twice.
- No skipped test results were found. The final runner `--skip` filter excludes only suites already run in the preceding six isolated batches; it is not omitted coverage. `scripts/test-native.sh` at the tested SHA was read to verify that partition.
- Full Xcode 26.6 (17F113); Swift test target x86_64-apple-macos14.0. `WIRE_AUDIT cases=52 protocol_violations=0` is local simulated protocol coverage, not live paid cloud acceptance.

## Real foreground targets

| Target | Result | Evidence |
|---|---|---|
| Owned AppKit NSTextView | PASS | `foreground/input-foreground-batch.log` |
| Owned WKWebView | PASS | `foreground/input-foreground-batch.log` |
| TextEdit, new document | PASS | `foreground/textedit.log` |
| Chrome, disposable profile/document | PASS | `foreground/chrome.log` |
| Edge, disposable document | PASS | `foreground/edge.log` |
| Safari, disposable document | PASS | `foreground/safari.log` |

All six verify first insertion, duplicate suppression, UTF-16 suffix append, surrounding content, and stale target rejection. Chrome's additional focus-timeout injection also passes (`chrome-focus-timeout.log`). Browser DOM witnesses confirm exact content with zero Enter/submits after manual edit, cancellation and target switch. The plain TextEdit artifact has no DOM send counter; it must not be represented as one.

WKWebView separately passes longer/shorter correction, manual edit, blur, restart, silent-context and held-AX cancellation cases. AppKit verifies ignored-write, manual-edit, cancellation and other-window rejection with no replay or sends. WKWebView's first AX mutation reports a timeout and is confirmed by readback; that event is retained, not relabeled as a successful setter response.

The artifacts use synthetic content in disposable CI GUI sessions. They do not establish current user-workstation/browser/microphone acceptance. The original failures at runs 45530413100 (`880840e`) and 45552530436 (`fb3c361`) remain preserved separately; this passing run does not retroactively identify their unlogged underlying AX error.

## Standard Sparkle interface

`standard-update-ui/` records **PASS** for actual SDK `SUUpdateAlert` display, exact inline release notes, enabled standard buttons, actual `Remind Me Later` button action, closed dialog, and restored controller readiness. The screenshot was viewed and its SHA-256 verified. Only the loopback appcast was requested; public network access was denied; no update archive or installation was requested.

This is an x86_64 presentation fixture using the unchanged product controller and SDK default user driver, **not the complete signed product app**. The fixture retains its own build 574 metadata. Its receipt explicitly reports `source_dirty=true`; that fact is preserved. Product controller, probe and source-icon hashes were independently compared to Git blobs at the frozen 577 SHA and match. This is precise input binding, not an invented clean-checkout assertion or full upgrade receipt.

## Evidence integrity and remaining scope

`run-logs.zip` is the complete GitHub run-log ZIP; `run-logs/` preserves every member. Foreground and standard-update-UI ZIP hashes both match GitHub's artifact `digest` and SHA binding. `receipt.json` contains job IDs, counts, markers and source bindings. `SHA256SUMS.txt` covers this collection.

An initial `gh run view` request rejected the unsupported `--allow-escape-sequences` option locally, before a network request; the API ZIP download succeeded. The tool failure is retained in `fetch-receipt.json`. Raw download stderr is excluded to avoid disclosing ephemeral signed URLs.

This review makes no new speech-quality, package-signing, notarization, Gatekeeper, upgrade/rollback or private-cloud claim. The separate brand workflow 45576254661 is not marked green here; its manifest correction and final CI remain root-owned. No product, workflow, assertion or user data was changed.
