#!/bin/bash
# Historical entry point retained; packaging/VERSION names the current prerelease.
set -euo pipefail
cd "$(dirname "$0")/.."
SAYTILE_STAGE="$(mktemp -d /tmp/saytile-package.XXXXXX)"
trap 'rm -rf "$SAYTILE_STAGE"' EXIT
SAYTILE_VERSION="$(cat packaging/VERSION)"
SAYTILE_DMG="Saytile-$SAYTILE_VERSION-arm64.dmg"
guide=docs/V1-INSTALL.md
if [[ "${SAYTILE_MANDARIN_CANDIDATE:-0}" == 1 ]]; then
  source_sha=$(git rev-parse HEAD)
  build_number=$(git rev-list --count "$source_sha")
  guide=docs/INTERNAL-INSTALL.md
  SAYTILE_DMG="Saytile-$SAYTILE_VERSION-$build_number-arm64.dmg"
fi
SAYTILE_DMG_OUTPUT="${SAYTILE_DMG_OUTPUT:-dist/$SAYTILE_DMG}"
mkdir -p "$(dirname "$SAYTILE_DMG_OUTPUT")"
if [[ -e "$SAYTILE_DMG_OUTPUT" ]]; then
  printf 'Refusing to replace an existing DMG candidate: %s\n' "$SAYTILE_DMG_OUTPUT" >&2
  exit 64
fi
# Sign and verify the image before exposing a final filename. The hard link
# publishes without overwriting another concurrent packager's finished image.
image_stage=$(mktemp -d "$(dirname "$SAYTILE_DMG_OUTPUT")/.saytile-image.XXXXXX")
trap 'rm -rf "$SAYTILE_STAGE" "$image_stage"' EXIT
image="$image_stage/candidate.dmg"
app="$SAYTILE_STAGE/Saytile.app"
SAYTILE_APP_OUTPUT="$app" scripts/build-app.sh release
if [[ "${SAYTILE_MANDARIN_CANDIDATE:-0}" == 1 ]]; then
  plist="$app/Contents/Info.plist"
  [[ "$(plutil -extract CFBundleDisplayName raw "$plist")" == Saytile ]]
  [[ "$(plutil -extract CFBundleVersion raw "$plist")" == "$build_number" ]]
  [[ "$(plutil -extract CFBundleIdentifier raw "$plist")" == app.saytile.mac.mandarin-candidate ]]
  [[ "$(plutil -extract SaytileSourceDirty raw "$plist")" == false ]]
  [[ "$(plutil -extract SaytileSourceRevision raw "$plist")" == "$source_sha" && "$(git rev-parse HEAD)" == "$source_sha" ]]
  distribution/sign-app.sh "$app" "${SAYTILE_SIGN_IDENTITY:?Developer ID identity is required for the internal build}"
fi
ln -s /Applications "$SAYTILE_STAGE/Applications"
cp "$guide" "$SAYTILE_STAGE/安装与使用.txt"
hdiutil create -volname "Saytile $SAYTILE_VERSION" -srcfolder "$SAYTILE_STAGE" -format UDZO "$image"
if [[ "${SAYTILE_MANDARIN_CANDIDATE:-0}" == 1 ]]; then
  codesign --force --timestamp --sign "$SAYTILE_SIGN_IDENTITY" "$image"
  codesign --verify --strict "$image"
fi
hdiutil verify "$image"
ln "$image" "$SAYTILE_DMG_OUTPUT"
shasum -a 256 "$SAYTILE_DMG_OUTPUT" > "$SAYTILE_DMG_OUTPUT.sha256"
printf 'Packaged %s\n' "$SAYTILE_DMG_OUTPUT"
