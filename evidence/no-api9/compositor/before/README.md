# Two-window ScreenCaptureKit measurement

The narrow test compiled the unchanged `InputPanelWindowView`, `InputPanelView`, `ReferencePanelSurface` and their dependencies from `341523df9c961e3ff872514a2bbea565ee2e52d3`, tree `691da3c504e4f3ac19f3f60c8d071b93c236d816`. It linked a SaytileKit library compiled at `69b90939fd688b35448f976950e96db0ce5b602a`. All SaytileKit, CAudio, CSQLite and package inputs matched between these two commits. This is a separate presentation experiment. The 69b90939 release images, full test suite and endurance results have their own scope.

The production surface did not change color when the synthetic backing changed. A bare Aqua NSVisualEffectView with the same active popover material and behind-window blend mode also showed zero RGB change. Transparent and translucent controls clearly transmitted the backing color. This result does not isolate a defect in SwiftUI clipping, the production shadow or the ordinary desktop render. Blur of a real wallpaper remains unverified.

| Front window | Warm minus cool interior, sRGB8 | Six-point stripe contrast inside, cool |
| --- | --- | ---: |
| Product panel | 0.000, 0.000, 0.000 | 0.030 |
| Clear AppKit control | +166.007, −117.896, −45.528 | 38.850 |
| 45% white AppKit control | +89.521, −62.486, −23.521 | 20.764 |
| Bare active popover material | 0.000, 0.000, 0.000 | 0.000 |

The exposed cool stripe contrast was 38.850. The product interior stayed near (234.986, 234.985, 234.983) for cool, warm and cool again. Low contrast alone cannot distinguish blurring from an opaque fill. The controls show that this capture arrangement can measure ordinary alpha transmission. The experiment did not sample the unfiltered display, an ordinary foreground panel, private windows or the wallpaper.

## Capture boundary

A single process created two borderless panels below ordinary windows. Neither could become key or main, accepted mouse events or changed the wallpaper. The backing was opaque and extended 144 points horizontally and 120 points vertically beyond the test panel. The crop was 440 × 330 points, inside that controlled area. The test obtained redacted current-process shareable content and passed exactly its own two WindowServer IDs to the window-inclusion content filter. It checked the returned owner and ID set before sampling. This Apple filter excludes the desktop and Dock. Menu bar, cursor, child windows, audio and microphone were disabled. Only aggregate sRGB statistics from two small regions were written. No composed frame was saved. [Apple window inclusion initializer](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init%28display%3Aincluding%3A%29)

The read-only screen capture preflight passed. The actual Reduce Transparency setting was off. No authorization request, system setting change or global input event was issued. The foreground process stayed unchanged, there were zero activation notifications and the probe never activated. The immutable executable exited normally in 6.795 seconds. The earlier product-only run produced its measurements, closed the windows and was terminated at its 15-second deadline because its application event loop remained open. Its raw records are in `initial-product-observation/`.

## Reproduction

Use a fresh temporary output directory and a known SaytileKit build with identical inputs. The runner verifies source equality and hashes the static library, tested Swift sources, runner and executable. It selects the main display ID, confirms two owned windows and aborts on a failed preflight or changed foreground. The capture has an 18-second outer deadline. It does not launch or install the ordinary application.

```sh
python3 run-owned-glass.py \
  --repo /path/to/saytile \
  --revision 341523df9c961e3ff872514a2bbea565ee2e52d3 \
  --library-revision 69b90939fd688b35448f976950e96db0ce5b602a \
  --library-scratch /path/to/verified-swift-scratch \
  --output /tmp/saytile-compositor-fresh-run
```

`measurements.json` contains every raw aggregate and filter fact. `summary.json` gives the warm-minus-cool deltas. `execution.json` and `source-identity.json` bind the run to the exact binary and Swift inputs.
