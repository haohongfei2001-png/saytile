#!/bin/bash
# Developer ID signing for an already-built local candidate.
set -euo pipefail
cd "$(dirname "$0")/.."
app=$1
identity=$2
[[ -d "$app" && "$identity" =~ ^[0-9A-Fa-f]{40}$ ]]
if [[ -x "$app/Contents/Helpers/SaytileSherpa" ]]; then
  for child in "$app/Contents/Frameworks/"*.dylib "$app/Contents/Helpers/"{SaytileSherpa,SaytileModelWorker}; do
    codesign --force --options runtime --timestamp --sign "$identity" "$child"
  done
fi
framework="$app/Contents/Frameworks/Sparkle.framework"
if [[ -d "$framework" ]]; then
  # Sparkle ships signed nested helper apps and XPC services. Preserve their
  # upstream signatures and sign the containing framework for library validation.
  codesign --force --options runtime --timestamp --sign "$identity" "$framework"
fi
codesign --force --options runtime --timestamp --entitlements distribution/audio-input.plist --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
