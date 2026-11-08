# Final isolated controller and input verification

Runtime `d4b9dbe812b9084f1bf31c1817c7b67095e17fc7`; source tree
`01f8644b57935f7f9beb9759ad3e8f44dda2ce30`. Four before/intermediate/after source
receipts match across **197 tracked Sources/tests/scripts/Package.swift files**,
with digest `5d32f0a084c0fdbbb9620006fc23e1b1667287235ea5c9718c6ae27921f54096`.
No production source, fixture or official script changed during these runs.

- `app-model.log`: **66 AppModel checks pass**. Connection lifecycle and
  credential-generation admission use injected evidence, not live cloud
  verification. `app-model-build.log` contains the build and probe output.
- `input-browser-dom.log`: **20 headless DOM checks pass** through the production
  Swift input coordinator and SQLite, using the existing test-only DOM adapter.
- `input-native-coordinator.log`: **9 checks pass** against a real owned
  background NSTextView via AX, including suffix-only insertion, selection
  changes, cancellation and at-most-once reservation.
- `input-webkit-observer.log`: **6/6 context/semantic observer checks**, two
  unsupported-context rejections and zero sends. The background AX setter still
  acknowledges without mutating the DOM value. That attempt is unverified once
  and never replayed; this is **not** evidence of successful browser insertion.

Native and WKWebView receipts both show `foreground_unchanged=true` and
`owned_activated=false`. These tests do not run the foreground target resolver,
open a visible browser, access a browser profile, type into a user application,
open the microphone or call a real model. The AX fixture window was serialized
with the other agent's owned-range checks; all of these probes exited before
that agent received the AX slot.

`receipt.json` contains source identities, executable/log hashes, Swift and
browser versions, and scope. AppModel's exact executed probe is retained in a
task-owned temporary directory and has matching hashes before/after execution.
`app-model-retained-runner.sh` is the established AppModel script with only its
working directory and disposable-output retention changed; the official script
and compilation inputs remain untouched. DOM and AX executable hashes are taken
after their scripts finish and retained executables remain available for audit.

The existing headless Chromium executable is selected through
`SAYTILE_CHROMIUM_EXECUTABLE`, avoiding the previously diagnosed missing default
Playwright executable. No dependency download, startup failure or rerun occurred
in this final run. Playwright is 1.65.0; headless Chromium is 156.0.8078.4.

Commands use `/tmp/saytile-final-d4b9dbe-model` and
`/tmp/saytile-final-d4b9dbe-input`, with `SAYTILE_MODEL_LOG` and
`SAYTILE_INPUT_EVIDENCE_DIRECTORY` pointing here. The DOM runner is
`scripts/test-input-browser.mjs`, and native/WKWebView use default
`scripts/test-input-native.py` without any foreground flag. Owned-range AX,
Apple, package UI and resource-soak results are separate final receipts and were
not duplicated in this task.
