# Integration receipt

PR5 fbe9349 includes PR4 45af670 and concurrent test-only revisions through51679a4. Integrated core59a63f2 without force-push. Four conflicts were fixture wording/defaults/scheduling expectations; kept new mandatory-GPT publication/final-review tests, retained exact credential-ID round-trip assertions, and made all obsolete file/audio review mock calls fail-fast rather than return evidence. No main/RC1 mutation. Final integrated native validation remains required; previous counts refer to their exact tested snapshots.

Integration validation caught a duplicate GPT fixture from an automatic merge, removed only the duplicate; production validation correctly rejected two cores. Full host run before this fix compiled and ran288 tests with exactly that one failure; isolated Keychain and silent-playback gates passed outside Codex sandbox.

Initial PR6 native CI passed native/AppModel/build/probe checks, then its UI fixture wrongly required the retired Gemini phase and removed fast-mode controls. Updated the fixture to assert one unchanged transcript during the single GPT processing/failure path; reduced only the two removed mode-control AX presses (16->14), retaining all remaining control/save/authorization checks. Final native UI rendering must still pass; this correction does not claim real external AX editing verified.

Owned-range repair introduces additive schema4 and preserves monotone insertion coordinates separately from effective text prefix. Updated standalone released-Beta/RC1 upgrade and crash-process checks to expect4, not3. Old App/old database backups are not touched; downgrade safety is checked only on disposable fixture copies.
