# Natural paragraph native review

Pre-package debug acceptance on the authorized Mac. Only four synthetic ASR-origin database rows and silent local audio were created; no microphone, ASR, cloud service, user data, global clipboard, or installed Saytile was used. Source/component hashes are in `source-receipt.json`; this is not the final signed package receipt.

## Passed

- Shared document fixture: 25,896 exact assertions, including every tested UTF-16 edit range, emoji/decomposed scalars, whitespace, generated boundary deletion, explicit hidden-boundary metadata, and undo/redo. The AppKit NSTextView/UndoManager case also ran.
- Three-second speech gap continues a paragraph; 15 seconds creates a paragraph inside its time group; 60 seconds creates a new group. Four original records remain four original owners, shown as three editable paragraphs in two time groups.
- Native main-board and archive text agree. Selected text/reading position and private clipboard snapshots survive late ASR; revision returns to its original position.
- Native archive editing crosses two original recordings, inserts an emoji, copies it, and undoes/redoes through the real NSTextView. SQLite text matches after each operation. A late machine result is retained as a revision but cannot replace the manual edit.
- Editing one word of the second archive paragraph retains its main-board newline.
- Existing independent NativeUIControlProbe inspected exactly one play/star pair per paragraph (30 × 28 pt each), then AXPress starred both original members and started/stopped the real AVAudioPlayer. Playback progressed beyond the first one-second source into the second source; silent audio is disclosed and is not speech validation.
- Every review window remained non-key/non-main and did not activate or change the foreground application.
- A second fresh run without the helper passed native editor, storage and playback semantics and correctly emitted `nativeControlActions.status = NOT_RUN`. Its play/star operations called the model, not AX; these are not counted as native button acceptance.

## Visual observation

Actual AppKit/SwiftUI views were rasterized with AppKit cacheDisplay at native 2× resolution. `natural-archive-reading.png` shows a clean archive with two sparse time labels and three paragraphs; controls are absent while not focused. `natural-archive-editing.png` shows the focused action pair. `natural-panel-after-edit.png` shows the same continuous, editable text and natural newlines in the approved panel. These files are real rendered product views, not HTML/mockups, but are not full-desktop captures or a final subjective design approval.

## Earlier probe failures

`superseded-probe-failures/` preserves the failed observations. An in-process home-grown accessibility traversal reached the AppKit text editors but omitted SwiftUI virtual buttons. This was a test traversal limitation, not a reproduced product-control failure. Run c reused the preceding binary after a compile error and therefore is not independent evidence. Reusing the project's existing external AX probe resolved the traversal issue without changing product controls or lowering assertions.

## Reproduction

Build the native AX fixture:

```sh
swiftc -swift-version 6 -parse-as-library tests/fixtures/NativeUIControlProbe.swift -o /private/tmp/saytile-natural-ui-control-probe
```

On the authorized Mac, run a signed or debug candidate with **new empty** data and image directories:

```sh
SAYTILE_NATURAL_PARAGRAPHS=1 SAYTILE_UI_CONTROL_PROBE=/private/tmp/saytile-natural-ui-control-probe /absolute/path/to/Saytile --data-directory /private/tmp/fresh-natural-review/data --ui-review /private/tmp/fresh-natural-review/images
```

Omit `SAYTILE_UI_CONTROL_PROBE` to check the no-helper path. It must keep the native controls NOT_RUN; any configured helper failure is fatal. Final signed same-SHA revalidation is separate and pending at this checkpoint.
