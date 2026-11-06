# Native first-connection workflow review

> **TEST_ONLY:** the “已接通，可以使用” screenshot uses an injected live-shaped report to test the real UI/controller admission branch. It is **not evidence of any live cloud connection or speech recognition accuracy**.

The final preview run is `ui-first-connection-final/manifest.json` and `ui-first-connection-final/run.log`; `ui-first-connection-final-control.log` records the complete command output. It passed **22 screenshots, 34 native AXPress actions, 6 AXSetValue actions, 6 owned native field-editor commits (including 3 SecureField commits), and 9 control groups**. The previous 15 screenshots and 6 groups remain covered.

The added flow starts with a new empty database and preferences. It actually opens each service header, fills Workspace and all three SecureFields, presses Save, grants each service's processing consent, expands costs, authorizes the check and presses Start. The actual production AppModel receives injected progress/results and its receipt gate enables the cloud setting. Separate native retry/cancel actions show three failed service rows or three stopped rows, and cloud remains off in those cases. Values are fixed fixture credentials; no production credential bytes are accessed.

The final costs/success/failure/cancelled screenshots were visually inspected. The cost explanation is genuinely expanded and readable; all three service outcomes are visible and distinct; cancellation removes pending states. The Form remains scrollable for lower settings. The review window stayed transparent/nonactivating, and the helper accessed only its explicitly supplied fixture PID/window. No global keys, microphone or user document was used.

The first-connection model uses `AppConnectionDependencies` with in-memory credential and verification functions and an inert configuration apply. Its success report is deliberately **TEST_ONLY live-shaped controller evidence**, not a real provider response, account validation or recognition-quality result. Earlier settings screenshots use existing scoped Keychain **metadata presence** queries only; the overall run must not be described as zero Keychain operations. No credential secret reads or provider network calls occur.

## Concrete interaction fix

Initial native disclosure actions returned success but left the service fields closed (0→0). A header HStack identifier was also inherited by two labels and combined in the disclosure identifier. Parent accessibility-action experimentation corrupted child TextField roles and was rejected by the regression. These observations do not establish a particular macOS framework defect or prove an initialization-race hypothesis.

The retained product change is explicit native Button headers with chevrons and local expansion state for the three service editors and the required costs explanation. IDs apply only to the buttons; SecureFields, text fields and their actions retain their native roles. `NativeUIControlProbe.swift` is restored to its original implementation: no ancestor/proxy fallback, coordinate click or model-state substitution remains. Other advanced DisclosureGroups were not expanded in this added workflow and are outside its action coverage.

Intermediate failed-run logs and manifests remain under `ui-first-connection-*`; repeated intermediate PNGs were removed, and those manifests are historical failure receipts, not complete image sets. Only `ui-first-connection-final/` is the accepted preview image set. This package reports the checkpoint revision with `source_dirty=true`; root's final runtime-SHA validation is a separate delivery step.
