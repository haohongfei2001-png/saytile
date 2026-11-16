# Feedback confirmation acceptance

## Observed failure

Source `b088b99a4b21a719088604b1236a16ba18f74b7a` (0.19, build 498) passed four of five GitHub checks. The native job in run `43721346057` passed release compilation, 548 Swift Testing cases, 30 inherited XCTest cases, 188 AppModel checks and 12 feedback-controller checks. It then failed in the owned native feedback fixture after a single `AXPress` on the withdrawal confirmation.

The Accessibility bridge returned `-25205` (`kAXErrorAttributeUnsupported`); the subsequently inspected button had no enabled attribute. The Send, status refresh and first Withdraw actions had already succeeded. The same signed source passed the local native fixture. These facts do not establish whether the failing CI confirmation executed: the old harness threw before recording the report state and transport counters. A dismissed SwiftUI confirmation invalidating its AX node is a plausible explanation, not a proven observation from that run.

## Verification boundary

The repair is confined to acceptance code. Product withdrawal, authorization and persistence behavior stay unchanged. Only the exact owned feedback confirmation can report an uncertain action response; uncertainty is never a passing result by itself. The harness must observe all of the following after the one action:

- the original delivered report transitions to confirmed deletion;
- exactly one deletion request is recorded by the isolated transport;
- the confirmation control is absent from a complete observation of the same owned window;
- the foreground application is unchanged.

No repeat press, focus acquisition or global relaxation of AX errors is allowed. An injected missing response after a real action must satisfy the same postconditions. An injected missing response with no action must fail them. Ordinary native controls continue to require their original success result.

The fixture uses synthetic feedback and an injected transport. A passing result establishes native interaction and local outbox behavior; it does not establish deployment or delivery to the private GitHub feedback repository. Final source-bound receipts and CI results are recorded separately after execution.

## Pre-commit checks (2026-11-16)

The modified helper compiles with Swift 6, the release executable builds, and Python syntax/diff checks pass. Independent review found and corrected a per-attribute AX read issue: a successful batch read can contain errors for individual attributes, so the feedback-only traversal now refuses incomplete containers. A raw unbundled WIP launch did not produce native evidence and is not counted as acceptance. The final clean signed app and complete CI remain the required execution checks.

## Signed build 499 and host isolation

The signed build 499 (`0243f7916f1ff14d869638d8eaf555a15c9c63d1`) failed locally before the confirmation action: opening the dialog was followed by the diagnostic process becoming frontmost. The helper refused to proceed. The no-action negative control retained the delivered report, zero deletion requests and the visible confirmation. Build 499 is not accepted even if its independent CI succeeds.

A separate native SwiftUI/AppKit probe demonstrated that confirmationDialog creates an `_NSAlertPanel` capable of becoming key, despite the original host panel refusing key/main status. One real confirmation action executed once and dismissed the dialog while its AX reply was -25205. The probe also verified an actual activation-policy change from accessory (1) to prohibited (2), with the same real AX confirmation still working and no self-activation. Accessory did not activate on every probe run; no deterministic activation claim is made.

The feedback-only diagnostic host now uses and asserts the prohibited policy before creating any window, removing its permission to activate. Production application policy and all other fixtures stay unchanged. Normal restart and both fault scenarios must record the actual prohibited policy. Final acceptance still requires the original foreground checks and all deletion postconditions.
