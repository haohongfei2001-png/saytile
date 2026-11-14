# Independent read-only runtime review

Reviewed the three source snapshots and hashes in `runtime-review-source/`. This is a source/interleaving review, not a claim that these schedules have already been reproduced with live AX applications. No runtime files, source HEAD, application, GPU, microphone or user data were changed.

## P1: successful resize can lose its restoration lease when cancellation occurs before move

`PanelWindowAccess.setFrame` performs resize and confirms its frame, then guards cancellation before the position write. That guard returns nil for cancellation even when the fresh frame still exactly equals the successful resize. `PanelArrangementWorker` records a new lease only when a non-nil changed frame is returned. Result: a real size mutation can remain after mode-off/stop without any lease to restore it.

This is not limited to a user cancel: `PanelWindowEvents` routes the app's own AXResized notification through `changed()`, which cancels the in-flight token. On a previously observed ordinary window, the native resize notification can arrive between those two writes. A bounded fixture should force cancellation after size readback and before position, then verify the original frame can be restored. Minimal fix: on cancellation only, retain/return the precisely owned partial resize; if current frame or identity no longer matches, continue refusing ownership. Do not blindly complete a move after user cancellation.

## P2: restoration ownership tolerances disagree

The controller's `same` accepts up to one logical point, whereas the AX bridge uses 0.25 point. A user 0.5-point move is therefore not recognized as transferring the lease back. If the panel later requires another relocation, the worker may carry forward the old pre-user `original`; a later mode-off restoration can erase that user move. Use the stricter ownership comparison for leases and preserve any larger tolerance only for visual/debounce decisions.

## P2: full-screen geometry can override a trustworthy ordinary-window signal

CG full-screen-sized geometry sets `fullscreen=true` first. Later AX observations can add a positive native full-screen result, but cannot reject it when the same matching window is standard and explicitly `AXFullScreen=false`. Ordinary windows can fill the full display when menu bar/Dock space is not reserved. In that case boundary reservation is suppressed as if the app entered native full screen. A specific native fixture should cover a normal AX standard window with full-display bounds. Prefer a trustworthy AX ordinary-window denial; retain the geometric fallback for genuinely borderless or unknown windows.

## Observer lifecycle observation

Updates and stop are serialized on the observer queue. The controller waits for event teardown and in-flight work before its final conditional restoration; stale generations do not apply panel moves. I found no demonstrated callback use-after-free in the current main-run-loop/await teardown ordering.

The `registered` set is only pruned when a PID disappears from all snapshots, not when one window closes while its process keeps other windows. This leaves stale registration keys during long sessions. PIDs also key observers without a launch identity, so a rare rapid PID reuse can retain an observer belonging to the previous app instance. These are bounded-scope cleanup concerns; they do not establish an unsafe write because the bridge separately verifies app launch identity and window ownership.

## Verified positive constraints

- Single in-flight worker avoids concurrent lease mutation.
- Every ordinary mutation rechecks AX/CG window identity, current geometry, writable status and mouse buttons.
- Old plans are canceled before subsequent writes and discarded at controller apply.
- Full-screen controls come only from focused geometry and shallow structural/toolbars; no text/value/title contents or web/document traversal is performed.
- Normal access is off the main/audio queues, and no activation or input events are generated.
