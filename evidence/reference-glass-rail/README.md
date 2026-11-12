# Native comparison with the supplied sidebar artwork

[Default native rail side by side](default-hosts-top.png) · [Complete native windows and reference](reference-and-native.png) · [Effect-artwork width](reference-and-artwork-width.png) · [Measurements](reference-metrics.json) · [WindowServer and Accessibility receipts](comparison.json)

The original raster is 1672 × 941. The outer sidebar spans approximately x=1347–1672; its first card spans x=1362–1657 and y=54–195. The original SHA-256 is `c15bc20b8bd33e1f99f21638b81234748d1e17f2c3aefea518d9c2989e750ca2`.

## Native results

| Observation | Result |
| --- | --- |
| Saytile source checkout and executable | `ce2d5cfa3f36166850a667063cd51c3ea55c6d25` · `69315df83c1327775f6d9581cc645e0022ba54361180fc96243be85e7889828f` |
| Nearpane source checkout and executable | `45093101e904de5af0784656db062f7e47ad7b6d` · `febf6895e2ad3f967cf8fd6d5fb3e59d1983831b4536fe4c4e76f9a1c423d680` |
| Display | 1920 × 1080 logical points, scale 2; 2 attached screens |
| Default rail | Saytile 240 × 128 pt; Nearpane 240 × 1080 pt. Outer left edge, right edge and top agree. |
| Text and controls | Both hosts presented the same reference sentence and selectable text. AX reported the native font at 14.40 pt at default width. All three states passed frame, label, font and controlled-material checks. |
| Copy | Pressed the actual copy control on each app's private pasteboard. Both the whole group and a two-character selection matched exactly. |
| Reference scale | Nearpane 374 × 1080 pt, displayed at the reference width for visual comparison. Font size 22.44 pt, native inner-card aspect 2.108, reference 2.092. |
| Screenshot tray | Three imported PNG files of real AppKit fixture views, archived through the normal Riftlet importer, plus the actual camera control. |
| Workspace | Four owned AppKit document windows acquired through the signed desktop helper and real ScreenCaptureKit. The sidebar exposed four rendered preview nodes at both widths. No Space membership was observed; these are four read-only window previews. |

Each executable was launched from a temporary development directory, with isolated data and an ad-hoc signature verified with `codesign --verify --strict --deep`. The two exported layers belonged to the launched fixture process. The generated violet-to-blue backdrop, test state and four generated document contents were the external inputs. The actual text editor, button views, trays, menus and compositing came from the native products. Voice input was injected through the pre-existing review seam. Live microphones, recognition quality and user desktops were outside this visual test.

The separately launched Saytile window shows a transient overlay scroll indicator in the speaking-frame capture. The static artwork depicts no overlay indicator. The original artwork and each complete captured window were scaled uniformly to a common width. Visual differences remain in the synthesized documents, native inactive window chrome, source desktop aspect and the illustrated arrangement of workspaces. The measurements do not constitute a subjective visual approval.

## Reproduce

Pass two temporary signed application bundles and a writable isolated Nearpane checkout to `scripts/compare-host-voice-windows.py --also-artwork-width`. Run `scripts/compare-sidebar-reference.py --reference <original.png> --capture <output>` on its result. Both commands require macOS and Pillow. For capture and AX assertions the launching development tools require the existing screen recording and accessibility grants.
