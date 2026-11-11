#!/bin/bash
# Private review image, never installs or publishes. Sign with the existing Developer ID.
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(cat packaging/VERSION)
case "$version" in
  *-timeline.integration.*) volume="Saytile RC2 Integration";;
  *-integrated.*) volume="Saytile V1 Candidate";;
  *-local-asr.*) volume="Saytile Local ASR Candidate";;
  *-cloud.integration.*) volume="Saytile Cloud Candidate";;
  *) exit 64;;
esac
out="$PWD/dist/Saytile-$version-arm64.dmg"
[[ ! -e "$out" && -z "$(git status --porcelain -- Sources packaging scripts/build-app.sh Package.swift)" ]]
stage=$(mktemp -d /tmp/saytile-rc2-integration.XXXXXX)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/volume" dist
app="$stage/volume/Saytile.app"
if [[ "${SAYTILE_PERSONAL_EXPERIENCE:-0}" == 1 ]]; then
  app="$stage/volume/Saytile 个人体验.app"
  volume="Saytile 个人体验"
fi
SAYTILE_APP_OUTPUT="$app" scripts/build-app.sh release
identity=$(security find-identity -v -p codesigning | awk '/Developer ID Application/ {print $2}')
[[ "$identity" =~ ^[0-9A-Fa-f]{40}$ ]]
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
hdiutil create -quiet -volname "$volume" -srcfolder "$stage/volume" -format UDZO "$stage/integration.dmg"
codesign --force --timestamp --sign "$identity" "$stage/integration.dmg"
codesign --verify --strict "$stage/integration.dmg"
hdiutil verify "$stage/integration.dmg"
mv "$stage/integration.dmg" "$out"
shasum -a 256 "$out"
