#!/bin/bash
# Private review image, never installs or publishes. Sign with the existing Developer ID.
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(cat packaging/VERSION)
[[ "$version" == *-timeline.integration.* ]]
out="$PWD/dist/Saytile-$version-arm64.dmg"
[[ ! -e "$out" && -z "$(git status --porcelain -- Sources packaging scripts/build-app.sh Package.swift)" ]]
stage=$(mktemp -d /tmp/saytile-rc2-integration.XXXXXX)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/volume" dist
app="$stage/volume/Saytile.app"
SAYTILE_APP_OUTPUT="$app" scripts/build-app.sh release
identity=$(security find-identity -v -p codesigning | awk '/Developer ID Application/ {print $2}')
[[ "$identity" =~ ^[0-9A-Fa-f]{40}$ ]]
codesign --force --options runtime --timestamp --entitlements distribution/audio-input.plist --sign "$identity" "$app"
codesign --verify --strict "$app"
hdiutil create -quiet -volname "Saytile RC2 Integration" -srcfolder "$stage/volume" -format UDZO "$stage/integration.dmg"
codesign --force --timestamp --sign "$identity" "$stage/integration.dmg"
codesign --verify --strict "$stage/integration.dmg"
hdiutil verify "$stage/integration.dmg"
mv "$stage/integration.dmg" "$out"
shasum -a 256 "$out"
