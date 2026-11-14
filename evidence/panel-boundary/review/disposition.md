# Independent review dispositions

Static reviews were performed by two independent reviewers. Initial observations are preserved separately and are not described as runtime reproductions.

1. Own AX moved/resized callbacks must not cancel the two-step resize/move. They now only schedule a read. Explicit mode/visibility/Space decisions still cancel immediately.
2. Each AX write rechecks cancellation. If resize succeeded but position is cancelled, only an exact observed owned partial frame is returned for restoration tracking.
3. Failed/unknown restoration is retained as unresolved, not reported as completed or blindly replayed.
4. Restoration ownership uses the same 0.25 logical-point tolerance as the bridge. User geometry changes release the previous original.
5. Trusted AXFullscreen=false on a standard maximized window outranks full-display geometry fallback.
6. Native fullscreen/Space transitions retain the original ordinary-window lease until the same window returns.
7. AX observation registration is off the main actor. Native text/audio work is not blocked by a target's AX timeout.

Runtime receipts separately verify implemented behavior. No ASR/default model/storage changes are part of this branch.
