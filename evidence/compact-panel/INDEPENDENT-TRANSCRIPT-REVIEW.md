# Independent compact transcript review

Reviewed the current `CompactTranscriptView.swift`, `InputPanelView`, their existing AppModel actions, and the compact-panel design. This review did not modify those production files. The view owner applied the one reproduced fix below. Audio, recognition, Store, and external-input runtime are outside this UI change and were not altered or revalidated by this probe.

## Reproduced defect and resolution

The initial view compared Swift `String` values with `==` / `!=` when accepting updates, detecting deferred updates, and applying text. These comparisons treat canonically equivalent Unicode strings as equal. A revision from decomposed `cafe\u{301}` to composed `café` was therefore discarded: the visible NSTextView retained 5 UTF-16 units while the requested model transcript had 4. The independent real NSTextView probe failed at zero-based case 2. This is a text/selection consistency defect even though the two strings look equivalent.

The owner replaced all three comparisons with exact `utf16.elementsEqual`. The existing common-prefix/suffix patch and composed-character boundary widening remain intact. The exact red view SHA-256 was `e524ea82b2f6f0e00b0ca13b248c6364a1ffa511e78ce36891854729b1a93f42`; the green view SHA-256 is `3d658bfc6349ad8813cea4c992a2867c179dd00e6b6a077dbc98870a9f3fb72a`. The original failure is retained in `transcript-red.log`, not replaced by the green result.

## Bounded native verification

`TranscriptReview.swift` compiles the production view directly, uses actual NSTextView/NSTextStorage/layout, sets application activation policy to prohibited, and creates no window. It neither reads nor writes the clipboard, microphone, user document, private preference, production database, or external target. It uses no cloud request.

```sh
mkdir -p /tmp/saytile-compact-text-review
swiftc -swift-version 6 -parse-as-library \
  Sources/SaytileApp/CompactTranscriptView.swift \
  evidence/compact-panel/TranscriptReview.swift \
  -o /tmp/saytile-compact-text-review/probe-green
/tmp/saytile-compact-text-review/probe-green
```

The green result checks **10 exact Unicode updates** (Chinese/English, numbers and negation, surrogate-pair emoji, composed/decomposed accents, combining marks, ZWJ families/professions, skin modifiers, flags, empty text and deletion), plus **5 interaction checks**: selected text remains unchanged until explicit release, a selected normalization update is correctly deferred, selected text can be explicitly cleared, appending preserves a manually scrolled viewport, and a prepended paragraph preserves the prior reading character. All pass with the same NSTextStorage object, `window_created=false`, and `app_active=false`. These are scoped probe checks, not additional Swift Testing suite counts or evidence of human use.

## Contract review

- The normal update path modifies a UTF-16 range in the existing text storage. It widens boundaries that fall inside a composed character; it does not reset the whole native view or call `makeFirstResponder`.
- Active mouse selection and a retained nonempty selection defer the displayed revision. The model's latest text continues to update. “回到最新” explicitly releases the selection, applies the pending revision and resumes following.
- Reading away from the bottom disables automatic following. Appends preserve the viewport; text inserted above it preserves a character-based reading anchor. Resizing remains bounded by the containing NSPanel and text scrolls internally.
- The More menu delegates to the existing `setDirect`, `bindTarget`, and `insertRecent` actions. Choosing direct mode alone does not bind a target or send text; disabling it invalidates the binding. Manual insertion still freezes revision IDs and uses the original target validation, range ownership and no-replay behavior. This UI introduces no Return/Send action.
- Hiding or closing the main panel calls only `orderOut`. Capture start/pause/continue remains the single AppModel action. Archive editing remains separate and its draft protection is unchanged.
- The main panel exposes one read-only transcript, one capture control, compact state labels and lower-frequency menu actions. It does not expose model candidates or create an additional desktop launcher.

No additional definite P0/P1 defect was found in this scope after the Unicode correction. Exact packaged window focus/geometry, native menu/AX actions, keyboard and accessibility behavior, and visual composition remain the coordinated candidate UI verification's responsibility. Pure geometry and a hidden native text view do not establish physical display switching, real microphone behavior, or third-party input success.
