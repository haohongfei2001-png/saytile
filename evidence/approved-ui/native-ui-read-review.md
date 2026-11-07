# Independent native UI engineering review

Reviewed `Views.swift`, `Theme.swift`, `VoiceEntryView.swift`, `SaytileApp.swift` and the existing placement helper against the approved 538e2d8 specification. This was a source/call-path review; no additional visible window, real keyboard target, microphone or cloud request was started. Original reference-image bytes were unavailable, so color sampling and pixel/visual equivalence are not certified.

Three concrete findings were routed to root:

1. Menu-bar tooltip/AX state subscribed only to audio state and `hasStarted`, so current post-speech ASR completion could leave cached “recognizing” text stale. Root added current-record and settled-state publishers, retaining next-main-turn reads; reviewed the new subscription.
2. Diagnostic flags could construct AppModel/Store using the production directory before a late empty-directory guard. The shared pre-Store validator and ConnectionSetup reuse now have 9 focused passing tests; root wired it before any AppModel construction. Evidence is in `diagnostic-boundary/`. No production archive was accessed for reproduction.
3. The optional entry's raw 42-point rectangle could exceed a visible area smaller than its 58-point offset-plus-size requirement. Root now applies the existing placement clamp. An additional implementation note was sent: disable the entry hosting view's intrinsic sizing propagation when geometry is intentionally constrained below 42 points, matching the main panel's existing treatment.

The reviewed entry action calls only `showPanel`. Showing the main panel hides the entry first; hiding it updates the optional entry and does not toggle capture. Entry windows cannot become key/main; diagnostic preferences default the feature off, and diagnostic entry creation requires the explicit transparent focus-probe path. Normal main-panel text selection remains intentionally available through the actual VoicePanel. Screen-parameter restoration updates both window placement and entry visibility. No other concrete defect was found in these inspected paths; root's native interaction/focus evidence remains necessary for runtime acceptance.
