# Bottom controls and voice-driven standby — native evidence

Runtime head: `9d2d2346b867de67f59d874a656ee56af7e29f95`.
GitHub's tested merge: `da1a3bb7730647a4e234440cf24a9a088b791778`.
Both resolve to the identical full tree `8b566394102b779e16b17a4965ea001ecc5346fc`; the built app reports a clean source tree.

## Results actually observed

- [macOS native CI](https://github.com/haohongfei2001-png/saytile/actions/runs/42328995554): success; 391 Swift tests in 47 suites, 101 production AppModel checks, app packaging, CLI boundaries, isolated startup and native rendering.
- [Design contracts](https://github.com/haohongfei2001-png/saytile/actions/runs/42328995530): success; quality/provenance checks and the existing contracts/Unicode/DOM verification.
- 27 native SwiftUI/AppKit screenshots; synthetic capture states cover paused, listening, speech, standby while fusion is still running, and standby after finalization.
- The original artifact ZIP hash and every PNG hash were verified against the artifact metadata and `manifest.json` before retaining these files.
- The four PNGs here are unmodified original native renders. The complete 27-image set is in GitHub artifact `Saytile-native-ui-review` (ID13556537481; retention until2026-11-21), also enumerated in the preserved original manifest. The original UI `run.log` is retained.
- `native-ci-summary.log` contains clearly selected lines from the native CI job, not the full job log. The full log remains linked from the run.

## Visual review

The paused, speaking, post-VAD review and content PNGs were opened and inspected. They show no top control row; the footer contains copy on the left and the horizontal voice capsule on the right. Paused uses a play triangle, speech uses the measured-level bars, and the still-running background-review scene already uses the standby dot. The review and completed-standby images have the same hash, consistent with no extra completion state.

The supplied user attachment is a screenshot of the approved concept, not the original PNG bytes. This review checks layout, control count, symbols and continuous text. It is not original-image color sampling, pixel-perfect reproduction or user visual acceptance.

## Scope limits

This CI run is **render-only** (`controls_requested=false`): it did not execute cross-process AX presses, AXShowMenu selection or a physical microphone. The updated optional controls probe remains available and checks exactly two bottom controls, the empty-panel menu and real contextual edit/latest/navigation actions; do not describe those as executed here. Capture and service results are explicit synthetic dependencies. No real provider calls or private recordings were used.

The existing audio engine, saved-audio contract and transcription architecture were not modified. The no-api.5 installer/evidence in concurrent commit28ef90fc is preserved as a separate, older top-control baseline.
