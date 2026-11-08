# Compact native panel independent review

The actual production SwiftUI/AppKit panel passed the existing isolated native UI runner with controls. `ui-preview/manifest.json` has **passed=true**: **31 captures, 41 AXPress, 6 native menu selections, 5 control inspections, 6 AXSetValue, 6 native editor commits (3 secure), 12 control groups**, one native text/scroll test and one exact UTF-16 test. All interactions targeted only the synthetic fixture PID. Candidate activation was rejected; zero outside foreground transitions were observed.

This is a **dirty precommit preview**, built from baseline `e56a8631` plus the new source changes, not proof that baseline itself contained the compact UI. `ui-preview-source.json` identifies the checked source and binary. Root's final package run supplies the final commit and package identity.

## Actual checks

- The panel uses 320×200, 340×240 and 360×260 point viewports; long text uses 360×480. PNGs are Retina pixels, so the manifest separately validates point geometry and image pixel dimensions.
- The same single native capture button measured **36×36 points** in initial/listening/paused/preparing/interrupted states. Seven real AX button actions routed through the production AppModel to injected start/pause closures. The actual AudioController stayed paused; no microphone opened. The clicked sequence was start → pause → continue → listening → pause, preparing → cancel, interrupted → recover → pause. The added resume operation explicitly acknowledged listening state, the “聆听中” status and restored pause action before the next actual AX pause; `UI_NATIVE_CAPTURE_ACK` appears exactly once.
- The production read-only selectable NSTextView retained its selected old text and exact range while a Store-driven revision changed the selected region. Explicit native “回到最新” applied pending text and cleared selection.
- With the user scrolled upward, appending text preserved the viewport. Adding text above the viewport preserved the original visible character anchor instead of following the tail.
- Actual Store → AppModel → SwiftUI → NSTextView updates changed NFD café to NFC and back, comparing UTF-16 elements and length rather than Swift's canonically equivalent String equality.
- Real More-menu actions switched free/direct mode and routed archive/settings/hide. Clear removed only panel content; the saved revision remained available and was restored through the ordinary reuse path. Clipboard write, target binding and external insertion were not exercised by this UI fixture.
- Existing first-connection authorization, secure fields, failure/cancellation, and no-focus checks remain in the same run. Injected TEST_ONLY live-shaped receipts remain controller evidence only, not cloud acceptance.

## Preserved first failure and correction

`ui-preview-menu-ack-red/run.log` records AX menu selection returning success while the old immediate 80 ms model-state check still saw directMode=false. That is not evidence of completed state change. The test now awaits an explicit, bounded acknowledgement from the actual model (maximum five seconds), and records `UI_NATIVE_MENU_ACK direct_mode=true/false`. There was no production mode-menu implementation change to make this pass, no fixed longer sleep, and no weaker success condition. The same actual menu operation then completed both state transitions. Native menu action dispatch was asynchronous relative to AX return; the old button-oriented test assumed synchronous completion.

## Visual inspection

Inspected actual empty, content, 320×200 compact, selected/pending, latest/long text and interrupted captures. The panel has one transcript surface and a restrained status/header; text remains readable, the bottom controls do not overlap the final line, the interrupted reason is visible, and selection/new-text affordances are legible. A partially visible first line at a scrolled viewport boundary is ordinary clipping of scrollable content, not missing stored text; manual upward scrolling and exact complete-text assertions passed.

No additional confirmed P0/P1 was found in this review. Capture lifecycle and peer outcomes are injected; this run does not establish microphone/device behavior, real ASR quality, real cloud connectivity, or performance over long durations. The source/fixture code is now frozen for root integration. The earlier 39-press successful checkpoint is preserved in `ui-preview-39-press-checkpoint/`, with its original source identity and review. The requested follow-up adds only two actual AXPress operations to complete the resume chain and passes the same full UI checks. No full native suite or 30-minute soak was rerun for this test-only closure.
