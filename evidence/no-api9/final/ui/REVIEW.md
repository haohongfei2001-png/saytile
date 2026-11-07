# Packaged neutral glass input panel

Both review modes launched the arm64 App extracted from the read-only DMG for `dc26fe3c59ba55994d29e99ada8d2f0b49ad9886`, tree `f138f6733a642a2e53da22b3647aaf5744cb308b`. The executable SHA-256 is `cb3b7a38dae90fccd323b57ee746baedbfcb43b457e0b30dbdcbaedffd35ed00`. The DMG SHA-256 is `0bd16e511f3a1cf65a3618443ef3c498ca517786aa4ad07a0226451a0c2b449d`. The files matched the package identity; the 208 tracked inputs retained their recorded digest. [Package](../package-identity.json) · [Execution and image hashes](execution-receipt.json)

## Original geometry and text

The exact user-supplied JPEG in the repository has SHA-256 `58be88a019cf0241b1c540f799d0944ed294e650b8c119923a434a6e4889a7c5`. The comparison verifies that hash and normalizes both inputs to sRGB. The card crops at (130,250) in the original and (64,64) in the production window are the same size, 688 × 468 pixels. The original has an illustrated blue/violet wallpaper. The native image in the pair has its partial transparency displayed over neutral RGB (237,237,237). The side-by-side preserves scale. This comparison assesses geometry, type, copy mark and speech states. It does not score a white translucent material by the wallpaper's baked RGB. [Original](../../../../design/approved/Saytile-original-visual-reference-20261107.jpeg) · [Source dimensions](../../../../design/approved/original-reference-20261107.measurements.json) · [Same-scale pair](original-comparison-pair.png) · [Measurements](original-comparison.json)

| Component | Shipping App observation |
|---|---|
| Window | The three reference windows are each 816 × 596 px, or 408 × 298 pt. Their thresholded center-axis boundaries cover a 344 × 234 pt card with a 32 pt perimeter. The actual startup probe reported the same window bounds. |
| Body | All three reference text views reported native 19.5 pt type and a 316 × 166 pt viewport. The reference fixture preserves five explicit lines. Ordinary input wraps live text. Both images have five visible lines with small differences in line endings and glyph rasterization. |
| Footer | Eleven actual AX inspections measured copy at 42 × 33.5 pt and voice at 92.5 × 33.5 pt. Both bottom gaps were 18 pt. The gray double-square mark has approximate card-relative ink bounds [67,383,99,415) in the App and [66,382,99,414) in the JPEG. |
| Speech | Paused showed a triangle, standby one dot and recognizing five distinct violet bars. The recognizing end mark begins at card-relative (233,247) in the App and (238,244) in the reference. It was absent from the text region of the paused and standby images. |

[Paused](approved-reference/reference-paused.png) · [Standby](approved-reference/reference-standby.png) · [Recognizing](approved-reference/reference-recognizing.png) · [AX and PNG geometry](reference-measurements.json) · [Actual startup](../startup-focus.log)

## Material and backdrop evidence

The shipped surface uses a light behind-window popover material with opacity 0.35, a separate neutral white wash at 0.46 and neutral highlights/shadows. Reduce Transparency uses opaque cover values. The actual offscreen reference images show a partial-alpha neutral surface with violet speech/caret glyphs. Three same-row raw PNG samples had approximately equal RGB channel values of 221–222 with alpha 180. These particular images contain no matching illustrated wallpaper. [Surface implementation](../../../../Sources/SaytileApp/ReferencePanelStyle.swift)

The independent owned compositor ran the same production `InputPanelWindowView` over two controlled backgrounds. Switching cool to warm shifted its interior by (+22.507, −15.493, −5.507) in sRGB8, then switching back restored the cool value. This establishes real backdrop sensitivity on the tested Mac. It does not establish universal wallpaper fidelity, blur radius, translucency from an isolated PNG or user visual approval. [Controlled composite scope and results](../../compositor/README.md)

## Interaction

The controls run produced 37 ordinary images plus three reference windows. It recorded 45 AXPress actions, ten context-menu selections, six field edits including three secure fields, and eleven two-control inspections across 15 functional groups. Render-only produced 27 ordinary images plus three reference windows with zero AX actions. Both runs observed zero outside foreground changes. Corresponding reference PNGs were byte-identical. The first-connection service receipts used TEST_ONLY injected responses. [Controls](manifest.json) · [Render-only](../ui-render-only/manifest.json) · [Raw actions](run.log)

A separate detached production host verified seven reading/selection checks. Moving up two points during synthetic speech disabled the trailing marker, a Store revision preserved the active selection, and returning to latest applied the pending text and restored the marker. No window or activation occurred, and the actual audio controller stayed paused. Each UI mode independently rendered 71 diagnostic glyph poses. System Reduce Motion was not toggled. No physical microphone, real service, display timing or user acceptance was measured. [Reading receipt](caret-reading/receipt.json) · [Glyph scope](voice-glyph-audit.json) · [Independent review](../INDEPENDENT-REVIEW.md)
