#!/bin/bash
# Build a side-by-side preview from a clean product tree. Signing stays with macOS.
set -euo pipefail
cd "$(dirname "$0")/../.."
out="$PWD/deliverables/timeline-preview"
image="$out/Saytile-Timeline-Preview-arm64.dmg"
test ! -e "$image"
test -z "$(git status --porcelain -- Sources packaging Package.swift scripts/build-app.sh)"
mkdir -p "$out"
stage="$(mktemp -d /tmp/saytile-timeline-image.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
app="$stage/volume/Saytile Timeline Preview.app"
SAYTILE_APP_OUTPUT="$app" scripts/build-app.sh release
identity="$(security find-identity -v -p codesigning | awk '/Developer ID Application/ {print $2}')"
[[ "$identity" =~ ^[0-9A-Fa-f]{40}$ ]] || { echo "A unique Developer ID Application identity is required"; exit 1; }
cat > "$stage/audio.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>com.apple.security.device.audio-input</key><true/></dict></plist>
PLIST
codesign --force --options runtime --timestamp --entitlements "$stage/audio.plist" --sign "$identity" "$app"
codesign --verify --strict "$app"
cp docs/V1-TIMELINE-PREVIEW-INSTALL.md "$stage/volume/预览说明.txt"
hdiutil create -quiet -volname "Saytile Timeline Preview" -srcfolder "$stage/volume" -format UDZO "$image"
codesign --force --timestamp --sign "$identity" "$image"
codesign --verify --strict "$image"
hdiutil verify "$image"
(cd "$out" && shasum -a 256 Saytile-Timeline-Preview-arm64.dmg > SHA256SUMS.txt)
