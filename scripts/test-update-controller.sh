#!/bin/bash
# Actual controller + pinned Sparkle, without a feed, UI, Keychain or microphone.
set -euo pipefail
cd "$(dirname "$0")/.."
products="${SAYTILE_UPDATE_PROBE_PRODUCTS:?Set the compiled SaytileKit product directory}"
modulemap="${SAYTILE_UPDATE_PROBE_MODULE_MAP:?Set the matching CAudio module map}"
sparkle="${SAYTILE_UPDATE_PROBE_SPARKLE:-$PWD/.build/sparkle}"
scratch="$(mktemp -d /private/tmp/saytile-update-controller.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
swiftc -swift-version 6 -warnings-as-errors -target arm64-apple-macos26.0 \
  -module-cache-path "${SAYTILE_UPDATE_PROBE_CACHE:-/private/tmp/saytile-update-probe-module-cache}" \
  -I "$products" -I "$products/Modules" -I Sources/CSQLite \
  -Xcc "-fmodule-map-file=$modulemap" -F "$sparkle" -L "$products" \
  -lSaytileKit -lc++ -framework Sparkle -Xlinker -rpath -Xlinker "$sparkle" \
  Sources/SaytileApp/AppUpdateController.swift tests/fixtures/AppUpdateControllerProbe.swift -o "$scratch/probe"
"$scratch/probe"
