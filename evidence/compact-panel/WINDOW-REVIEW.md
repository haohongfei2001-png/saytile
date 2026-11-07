# Compact panel window and menu integration

This change owns `SaytileApp.swift`, `WindowPlacement.swift` and the corresponding geometry tests. It implements the confirmed compact-panel design without changing audio, recognition, Store or external-input behavior.

The first panel presentation is **340 × 240 logical points**. User resizing is bounded to **320 × 200 through 360 × 480**, further reduced only when the screen's visible area cannot contain the normal minimum. An 8-point safe margin respects menu-bar/Dock exclusions and negative display origins. SwiftUI intrinsic-size propagation is disabled for the panel hosting view: transcript growth must scroll inside the selected frame. Reopening preserves the session's moved/resized frame; disconnected displays restore onto the display with greatest overlap or nearest remaining center. Archive/settings retain their independent sizing.

The panel remains floating, nonactivating, join-all-Spaces and full-screen auxiliary. Display changes and completed resize operations clamp it back inside a visible frame. Closing or hiding the panel only orders the window out; it does not call pause/stop or change capture state. No desktop launcher, microphone startup or default visible second entry is introduced.

The menu bar reads the same derived product state and capture action as the panel. Silence while capture is enabled is labelled `聆听中`; beginning/paused/interrupted behavior follows AppModel's authoritative state. A Combine subscription to capture state and whether capture has begun replaces the old one-second status polling timer. Tooltip, image accessibility description and accessibility label agree. The right-click menu accurately says expand or collapse according to panel visibility and exposes the single applicable start/pause/continue/recover action.

## Verification plan and current status

The geometry suite covers default and bounded resize, negative/offset screens, constrained visible areas, logical-point scaling, moved-frame preservation, nearest-screen recovery after disconnect, legacy oversized frames and tiny positive screen geometry. There are 10 geometry tests including the retained general archive/settings recovery cases.

The first targeted build did not run tests because a concurrently edited UIReview call referred to `reviewCompactPanel` before its implementation was present. That build log is retained as `window-geometry-build-in-progress.log`; it is not counted as a test pass or an implementation failure in the window code. Once the shared interface was coherent, the focused run compiled the App and passed **10 tests in 1 suite**. The exact command was:

```sh
SAYTILE_TEST_SCRATCH=/tmp/saytile-compact-geometry \
SAYTILE_TEST_LOG=evidence/compact-panel/window-geometry.log \
scripts/test-native.sh --filter WindowPlacementTests
```

Two subsequent diagnostic-only log fields record the owned panel's `isKeyWindow` and `isMainWindow` at the beginning and end of the existing focus probe; the coordinated candidate build will compile these final logging additions. Runtime focus has not been inferred from the geometry tests.

After the source is coherent, build a separate candidate App under an owned `/tmp/saytile-*` path and use the existing `StartupFocusProbe` with its explicit isolated data directory. The existing `--focus-probe` now logs actual NSPanel frame/minimum/maximum/style/Spaces values, so the run can verify real 340 × 240 AppKit geometry alongside no foreground change. This probe opens no microphone or user document, never globally types, and does not replace RC1. No physical monitor rearrangement or scaling change will be performed; multi-display restoration remains a pure-geometry check until separately authorized native hardware validation.
