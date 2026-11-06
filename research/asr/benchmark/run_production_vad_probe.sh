#!/bin/bash
# Build an isolated temporary package from unchanged production source.
# macOS 26 / Swift 6. No edits to Sources or the main Package.swift.
set -euo pipefail
if [[ $# -lt 2 ]]; then
  echo 'Usage: bash run_production_vad_probe.sh INPUT.wav NEW_OUTPUT_DIR [--repeat N] [--active-tail]' >&2
  exit 2
fi
script_dir=$(cd "$(dirname "$0")" && pwd)
repo_dir=$(cd "$script_dir/../../.." && pwd)
cd "$repo_dir"
package_dir=$(mktemp -d "${TMPDIR:-/tmp}/saytile-vad-probe.XXXXXX")
trap 'rm -rf "$package_dir"' EXIT
mkdir -p "$package_dir/Sources/Probe"
ln -s "$repo_dir/Sources/CAudio" "$package_dir/Sources/CAudio"
ln -s "$repo_dir/Sources/SaytileKit/AudioJournal.swift" "$package_dir/Sources/Probe/AudioJournal.swift"
ln -s "$script_dir/production_vad_replay.swift" "$package_dir/Sources/Probe/Replay.swift"
cat > "$package_dir/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "SaytileProductionVADProbe",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "CAudio", exclude: ["WEBRTC-LICENSE.txt", "webrtc/common_audio/signal_processing/dot_product_with_scale.cc"], cSettings: [.headerSearchPath("."), .define("WEBRTC_POSIX")]),
        .executableTarget(name: "Probe", dependencies: ["CAudio"])
    ]
)
SWIFT
swift run --package-path "$package_dir" -c release Probe "$@"
git -C "$repo_dir" rev-parse HEAD > "$2/source-head.txt"
shasum -a 256 "$repo_dir/Sources/SaytileKit/AudioJournal.swift" "$repo_dir/Sources/CAudio/VAD.c" "$script_dir/production_vad_replay.swift" > "$2/source-sha256.txt"
