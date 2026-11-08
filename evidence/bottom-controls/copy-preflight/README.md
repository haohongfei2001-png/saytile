# Copy to an isolated native pasteboard

The development probe compiled the working AppModel with the production SaytileKit. It created a unique named NSPasteboard, a disposable Store and an isolated preferences suite, then ran without a window under `NSApplication.ActivationPolicy.prohibited`.

`AppModel.copy` wrote the supplied string containing a decomposed accent and an emoji. `copyRecent` wrote two Store records joined by a newline. Both writes advanced the named board's change count and matched the expected UTF-16 units. The synthetic capture remained listening with zero start/pause calls, and the actual AudioController remained paused. `defer` released the named board and removed the test data. The probe executable SHA-256 was `1612c9ed9723dbb0107c06ebca4a20ba246502802208c3bb83ad7f485dc20de7`.

The runtime keeps the existing `NativeInputCoordinator.copy(_:)` API. AppModel resolves `.general` when a user copies using its default configuration. An explicitly supplied board goes through the same native writer and produces the usual success notice only when `setString` succeeds.

This receipt covers the model and the native pasteboard writer during development. The package-level control review exercises `AXPress` on the visible copy button with actual NSTextView selection and current transcript content. That check is part of the single coordinated `scripts/test-native-ui.py --app <candidate.app> --output <output-directory> --controls` invocation.

The following commands reproduce the development probe from the repository root with Command Line Tools.

```sh
copy_scratch=/tmp/saytile-bottom-copy-verification
mkdir -p "$copy_scratch"
swift build --product SaytileKit --scratch-path "$copy_scratch/build"
copy_bin=$(swift build --product SaytileKit --scratch-path "$copy_scratch/build" --show-bin-path)
copy_module_map="$copy_bin/../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap"
if [ ! -f "$copy_module_map" ]; then copy_module_map="$copy_bin/CAudio.build/module.modulemap"; fi
swiftc -swift-version 6 -parse-as-library -module-cache-path "$copy_scratch/probe-module-cache" \
  -I "$copy_bin" -I "$copy_bin/Modules" -I Sources/CSQLite \
  -Xcc "-fmodule-map-file=$copy_module_map" -L "$copy_bin" -lSaytileKit -lc++ \
  Sources/SaytileApp/AppModel.swift evidence/bottom-controls/copy-preflight/CopyProbe.swift \
  -o "$copy_scratch/probe"
"$copy_scratch/probe"
```
