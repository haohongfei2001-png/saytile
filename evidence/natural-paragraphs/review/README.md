# Independent natural-paragraph integration review

This review uses the current isolated integration worktree, not installed user data. Exact working-file SHA-256 values are recorded in `receipt.json`. The base commit identifies the starting point only; the integration remains uncommitted while this report is prepared.

## Reproduced and addressed

1. **P1, inline edit data loss.** The original actual `ArchiveParagraphTextView` class was compiled unchanged with minimal synthetic host snapshot types and an injected save conflict. A hidden AppKit window successfully made the text view first responder. After a late snapshot arrived, inserting `我的` into `旧句` replaced it with `识别迟到的新句`; blur did not restore the user text. The old result is retained as FAIL, not recast as a passed test. The updated actual class keeps `我的旧句` after failed save, blur, and another late snapshot. Both sources, source bindings, and actual logs are included. The probe tests native local text retention only: it does not prove durable SQLite recovery or the full archive UI. The final AppModel additionally saves failed row edits through `preserveArchiveParagraphDraft`, retains another pre-existing draft as an immutable revision, and never selects the failed draft over a newer human edit. That path was read in source; its actual database persistence is a separate integration/Store test.
2. **P2, copy snapshot drift.** The context menu formerly captured the latest model paragraph while the focused text view intentionally held an older visible snapshot. The current menu reads `view.visibleSnapshot`; the Store combines that bounded rendered snapshot with remaining paragraph members using one SQLite statement. This avoids copying unseen late changes from the loaded native editor. This is a source review finding; final integrated native copy acceptance remains with the parent.
3. **P2, silent all-audio decoder failure.** When every existing chunk fails AVAudioPlayer decoding, playback records a skip notice and ends. The row displays notices only while playing. The current AppModel publishes `playbackNotice` to the archive notice if play returns already stopped. Existing missing-file failures already throw; this addresses the decode-failure path. No real recording was accessed.
4. **P2, refresh/member-navigation race.** A refresh captured outer archive window/query/filter but did not capture member-page navigation state. Changing member windows during an awaited read could publish one old member page before the queued pass. Parent now captures `requestedMembers`, reads only that snapshot, and compares `archiveMemberWindows == requestedMembers` before publication. This correction was verified in source; the complete native page-flow acceptance remains separately bound by the integration evidence.

## Other review conclusions

- Paragraph, recording, and revision identities remain separate. A visible paragraph has one bounded member window; whole-paragraph copy, playback, and starring query complete original IDs rather than truncating at that window.
- The focused summary is explicitly retained when new paragraphs push it outside the ordinary page. Its member window anchors at the prior first member, avoiding moving a focused editor merely because another original is appended.
- Search/star matching selects paragraph IDs first and then reads full membership. One matching fragment does not truncate the paragraph. Partial historical stars are intentionally treated as a starred paragraph; one click removes the entire paragraph star. New continuation members inherit an existing star.
- Explicit removed paragraph breaks now use separate `break_hidden` metadata, rather than inferring a join from an empty user-edited row. Both host maps forward the boundary before/after values; undo reverses them. A pure separator edit does not freeze unchanged ASR words as a human revision.
- Host mapping uses the shared UTF-16 edit mapper and commits a batch against original recording owners. It does not dispatch historical paragraph text to an external target. Late machine revisions remain immutable; the new Store guard protects newer human edits instead of letting a machine update veto explicit typing.
- No additional independently confirmed P0/P1 was found in the reviewed pagination, membership, star, filter, or copy paths. This is not a claim of exhaustive runtime coverage.

## Probe reproduction

Compile the recorded before/after pair with the real macOS AppKit SDK:

```sh
swiftc -swift-version 6 -parse-as-library ActualArchiveParagraphTextView.swift ConflictProbe.swift -o conflict-probe
./conflict-probe
```

Run in a disposable local directory. The probe creates a hidden window and uses synthetic strings only. No cloud, microphone, user archive, clipboard, or visible foreground app is used. The expanded after-fix host stubs only satisfy the class's new `visibleSnapshot` interface; they do not purport to test real ownership mapping.

## Final storage transaction review

The final `PanelEditTransaction.swift` and `TranscriptTimeline.swift` were independently read after the `break_hidden` and draft-preservation corrections. No additional confirmed defect was found. Boundary baseline/contradictory updates are validated before writes; every caller of `writePanelEdits` owns a transaction; boundary metadata and row revisions commit together. A separator-only update preserves live ASR preferred text. The Store initializer commits additive DDL, backfill, and sidecar version in the same SQLite transaction while retaining schema 6. Draft recovery validates every member before mutating, keeps a different pre-existing draft as an unselected immutable version, and never changes the preferred revision. The targeted regression sources include stale boundary, contradictory batch, ongoing ASR, reopen, and two-writer draft cases. This paragraph records a source review, not an independently rerun test count. Actual signed old/new reopen evidence belongs to the final rollback receipt.
