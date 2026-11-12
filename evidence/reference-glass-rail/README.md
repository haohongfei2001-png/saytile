# Native comparison with the supplied sidebar artwork

[Default native rail side by side](default-hosts-top.png) · [Complete native windows and reference](reference-and-native.png) · [Effect-artwork width](reference-and-artwork-width.png) · [Measurements](reference-metrics.json) · [WindowServer and Accessibility receipts](comparison.json)

The original raster is 1672 × 941. The outer sidebar spans approximately x=1347–1672; its first card spans x=1362–1657 and y=54–195. The original SHA-256 is `c15bc20b8bd33e1f99f21638b81234748d1e17f2c3aefea518d9c2989e750ca2`.

## Native results

| Observation | Result |
| --- | --- |
| Saytile embedded product source and executable | `d3ddafcd4d410fc763ae2a5badfaefa21ceb48fc` · `d068b8d633492ce3fb66b087a4da6d9daf72a798a570efb9151d04b210f68f82` |
| Nearpane source checkout and executable | `044b659f64146db0832f7c45a2d232512d7ddba5` · `3bc40e7f7db8de8254b6f1ee0de2cdaae503e018bafa91c94a452dd59d0543d0` |
| Display | 1920 × 1080 logical points, scale 2; 2 attached screens |
| Default rail | Saytile 240 × 128 pt; Nearpane 240 × 1080 pt. Outer left edge, right edge and top agree. |
| Text and controls | Both hosts presented the same reference sentence and selectable text. AX reported the native font at 14.40 pt at default width. All three states passed frame, label, font and controlled-material checks. |
| Copy | Pressed the actual copy control on each app's private pasteboard. Both the whole group and a two-character selection matched exactly. |
| Reference scale | Nearpane 374 × 1080 pt, displayed at the reference width for visual comparison. Font size 22.44 pt, native inner-card aspect 2.108, reference 2.092. |
| Screenshot tray | Three imported PNG files of real AppKit fixture views, archived through the normal Riftlet importer, plus the actual camera control. |
| Workspace | Four owned AppKit document windows acquired through the signed desktop helper and real ScreenCaptureKit. The sidebar exposed four rendered preview nodes at both widths. No Space membership was observed; these are four read-only window previews. |

Each executable was launched from a temporary development directory, with isolated data and an ad-hoc signature verified with `codesign --verify --strict --deep`. The two exported layers belonged to the launched fixture process. The generated violet-to-blue backdrop, test state and four generated document contents were the external inputs. The actual text editor, button views, trays, menus and compositing came from the native products. Voice input was injected through the pre-existing review seam. Live microphones, recognition quality and user desktops were outside this visual test.

The original artwork and each complete captured window were scaled uniformly to a common width. Visual differences remain in the synthesized documents, native inactive window chrome, source desktop aspect and the illustrated arrangement of workspaces. The measurements do not constitute a subjective visual approval. The speaking-state capture adds 1.8 seconds of settling time for both hosts; the initially visible macOS overlay scroll indicator was independently documented on the previous product build.

## Reproduce

Pass two temporary signed application bundles and a writable isolated Nearpane checkout to `scripts/compare-host-voice-windows.py --also-artwork-width`. Run `scripts/compare-sidebar-reference.py --reference <original.png> --capture <output>` on its result. Both commands require macOS and Pillow. For capture and AX assertions the launching development tools require the existing screen recording and accessibility grants.
