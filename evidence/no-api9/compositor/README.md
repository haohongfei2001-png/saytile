# Neutral panel material under two controlled backdrops

The release source is `dc26fe3c59ba55994d29e99ada8d2f0b49ad9886`, tree `f138f6733a642a2e53da22b3647aaf5744cb308b`. Its full production `InputPanelWindowView` transmitted a repeatable change in the underlying color. A cool-to-warm switch produced **(+22.507, −15.493, −5.507)** inside the card in sRGB8, and the color returned to its initial value on the second cool exposure. The same change was zero with the earlier neutral material at `341523df`.

| Surface | Warm minus cool interior in sRGB8 | Six-point stripe contrast inside, cool |
| --- | --- | ---: |
| Earlier production surface | 0, 0, 0 | 0.030 |
| Disposable 0.55 material trial | +8.000, −6.000, −1.553 | 2.089 |
| Disposable 0.35 material trial | +22.507, −15.493, −5.507 | 4.720 |
| Frozen 0.35 product | +22.507, −15.493, −5.507 | 4.720 |
| Fully clear AppKit control | +166.007, −117.896, −45.528 | 38.850 |
| 45% white AppKit control | +89.521, −62.486, −23.521 | 20.764 |
| Bare active popover material | 0, 0, 0 | 0.000 |

These values came from composed pixels sampled by ScreenCaptureKit. Stripe contrast is the mean absolute channel difference between samples six points apart in the controlled pattern. Color changed more at 0.35 than at 0.55. The frozen product retained the neutral white wash and left the transcript and buttons at their original opacity. The alpha setting belongs to the behind-window material layer only. When Reduce Transparency is active, the product requests the opaque fill. The test machine's setting was off and remained unchanged.

The actual selectable, read-only text view retained the synthetic string and a measured 19.5 pt font. The cool, warm and returning cool samples contained 491, 490 and 491 dark neutral ink pixels. The measured surface-to-median-ink contrast ratios were 11.69, 11.00 and 11.69. These numbers cover one short string, color space and display arrangement. The two positive controls demonstrate ordinary alpha transmission through the isolated capture. The bare AppKit material's fixed output prevents a separate claim about native background blur or arbitrary real wallpaper.

## Isolation and reproduction

The test uses `SCShareableContent.currentProcess` followed by a display filter including exactly two verified windows owned by the current process. One window is the opaque green/red striped backing. Its padded area fully surrounds the smaller nonactivating product window. Both sit below ordinary windows. No key or main window, global event, desktop capture, wallpaper read or new authorization was required. Cursor, menu bar, other windows, audio and child windows are excluded. Only numeric samples from a 440 × 330 pt region are written. No captured window image is saved. Foreground continuity held with zero activation notifications. [Apple window-inclusion filter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init%28display%3Aincluding%3A%29)

The final probe exited successfully after 6.826 seconds. The `final/` receipts bind it to the frozen source and the static library from that exact revision's full Swift build. `before/` retains the scoped earlier failure and controls. The two `trial-*/` directories preserve raw disposable results and their source differences from the engineering base. Their tested product source hashes disclose the single modified input. They remain separate from the final release's ordinary test count.

Run `run-owned-glass.py` in a new scratch directory using a library compiled from the stated revision. The reusable runner writes its compiler cache under its output directory. The exact runner used for the frozen measurement is preserved as `final/executed-runner.py`, which used a separately cleaned compiler cache. The compiled product inputs, probe and core behavior match.

```sh
python3 evidence/no-api9/compositor/run-owned-glass.py \
  --repo /path/to/saytile \
  --revision dc26fe3c59ba55994d29e99ada8d2f0b49ad9886 \
  --library-revision dc26fe3c59ba55994d29e99ada8d2f0b49ad9886 \
  --library-scratch /path/to/verified-swift-scratch \
  --output /tmp/saytile-compositor-fresh-output
```
