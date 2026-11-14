# Natural paragraph storage acceptance

This checks native SaytileKit + SQLite with generated data only. It does not open an installed archive, use a microphone, load ASR, upload audio, or modify a live app.

`final/receipt.json` binds the executed source files by SHA-256. The `baseline` field records the Git base while the product worktree is being integrated; it is not a claim that uncommitted changes were already part of that commit. The final product receipt must supply its own source SHA.

Run the same function bodies from `tests/SaytileKitTests/NaturalParagraphTests.swift`:

```sh
python3 evidence/natural-paragraphs/storage/run.py \
  --scratch /private/tmp/saytile-natural-kit-check \
  --output evidence/natural-paragraphs/storage/final
```

The runner removes only the Swift Testing import/annotations and invokes every test method directly against the current built static library. All condition checks and thrown failures remain. This provides native storage execution under the local toolchain; the complete Swift Testing run is a separate check. A real macro typecheck of the original test source is also recorded when the installed plugin is available.

Coverage includes 15-second natural paragraphs versus 60-second time groups, 135-member paragraphs traversed through bounded pages, whole-paragraph search/star/copy, late ASR versus deliberate edits, draft conflict preservation, undo/redo and stale boundary ownership, schema-6 compatibility, sidecar v1-to-v2 migration, deleted anchors, unchanged legacy rows, midnight/clock reversal, and durable-frame fallback. Explicit `break_hidden` metadata represents the removal of an automatic paragraph separator; a blank or edited text row alone does not imply that intent.

Original harness failures are retained under `fixture-failures/`:

- The first fixture produced a final revision but forgot to call `finishRecognition`, so reopening correctly recovered a still-running recognition. The fixture now closes the recognizer before checking unchanged rows; the equality assertion remains.
- The conflict fixture tried to save a human revision with `clearingDraftMatching` but without the required reviewed `basedOn` revision. The existing conflict protection correctly rejected this setup. Supplying its known base fixes the fixture without relaxing product protection.

- The first receipt wrapper counted `PASS` inside its summary as another test. All 11 bodies had passed; the wrapper now counts only lines beginning `PASS `. The original wrapper traceback is retained.

No source-level failure is converted to a skip. Simulator/Swift Testing CI and final native UI/installation receipts are reported separately by the integration task.
