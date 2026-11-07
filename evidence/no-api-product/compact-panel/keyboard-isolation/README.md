# Native UI fixture keyboard isolation

This is an additional isolation repair, not a failure of the preceding `ci-closure-fix` checks. The independent AX-target diagnostic found text/caret changes absent from its synthetic initialization; their source was not established. Review of this separate UI fixture found the same missing capability restriction: alpha zero, ignored mouse events and a nonactivating style did not themselves forbid becoming a key/main window.

Only UIReview now creates a private `ReviewPanel` with `canBecomeKey` and `canBecomeMain` both false. It checks both capabilities and actual `isKeyWindow`/`isMainWindow` before and after validation, after controls, for every captured view and before/after all six native field edits. No keyboard event characters are intercepted, read or logged. The real consumer `VoicePanel` is unchanged and retains its intentional ability to become key for text selection.

The new preview `/tmp/saytile-compact-keyboard-preview/Saytile.app` was built once. Original a684 and closure-only previews/evidence remain separate. Both complete modes ran against the same new binary, with unchanged assertions:

| Check | Render-only | Native controls |
| --- | --- | --- |
| Result | PASS | PASS |
| Native captures | 20 | 31 |
| Key/main isolation at capture | 20 | 31 |
| Validation before/after and interaction-after checks | 18 each | 22 each |
| Native field-edit isolation before/after | 0 | 6 each |
| AXPress / native menu selections | 0 / 0 | 41 / 6 |
| Capture inspections / resume acknowledgement | 0 / 0 | 5 / 1 |
| AXSetValue / native edits / secure edits | 0 / 0 / 0 | 6 / 6 / 3 |
| Control groups | 0 | 12 |
| Native text / exact UTF-16 checks | 1 / 1 | 1 / 1 |
| Outside foreground observations | 0 | 0 |

All recorded capability and actual key/main states were false. Existing candidate-activation rejection also passed. Owned field editors worked without keyboard focus, preserving the real SwiftUI delegate path. The manifest now requires the isolation counters to match captures and edit counts instead of recording them without enforcement.

`verification.json` records exact source/binary hashes, both manifests and the post-controls unchanged checks. `identity-pre-controls.json` was sampled after render-only launch and before controls; it is not claimed as a pre-render snapshot. This is a dirty preview atop a684, not a final committed candidate or live-cloud receipt. No provider call, microphone, global key posting, clipboard write or external target was used.
