#!/bin/bash
# Historical entry point retained; packaging/VERSION names the current prerelease.
set -euo pipefail
cd "$(dirname "$0")/.."
SAYTILE_STAGE="$(mktemp -d /tmp/saytile-package.XXXXXX)"
trap 'rm -rf "$SAYTILE_STAGE"' EXIT
SAYTILE_VERSION="$(cat packaging/VERSION)"
SAYTILE_DMG="Saytile-$SAYTILE_VERSION-arm64.dmg"
bundle_name="Saytile.app"
guide=docs/V1-INSTALL.md
if [[ "${SAYTILE_MANDARIN_CANDIDATE:-0}" == 1 ]]; then
  bundle_name="Saytile 中文识别候选.app"
  guide=evidence/mandarin-quality-20261114/INSTALL.md
  SAYTILE_DMG="Saytile-$SAYTILE_VERSION-mandarin-arm64.dmg"
fi
SAYTILE_DMG_OUTPUT="${SAYTILE_DMG_OUTPUT:-dist/$SAYTILE_DMG}"
mkdir -p "$(dirname "$SAYTILE_DMG_OUTPUT")"
if [[ -e "$SAYTILE_DMG_OUTPUT" ]]; then
  printf 'Refusing to replace an existing DMG candidate: %s\n' "$SAYTILE_DMG_OUTPUT" >&2
  exit 64
fi
SAYTILE_APP_OUTPUT="$SAYTILE_STAGE/$bundle_name" scripts/build-app.sh release
if [[ "${SAYTILE_MANDARIN_CANDIDATE:-0}" == 1 ]]; then
  plist="$SAYTILE_STAGE/$bundle_name/Contents/Info.plist"
  [[ "$(plutil -extract CFBundleIdentifier raw "$plist")" == app.saytile.mac.mandarin-candidate ]]
  [[ "$(plutil -extract SaytileSourceDirty raw "$plist")" == false ]]
  codesign --verify --deep --strict "$SAYTILE_STAGE/$bundle_name"
fi
ln -s /Applications "$SAYTILE_STAGE/Applications"
cp "$guide" "$SAYTILE_STAGE/安装与使用.txt"
hdiutil create -volname "Saytile $SAYTILE_VERSION" -srcfolder "$SAYTILE_STAGE" -format UDZO "$SAYTILE_DMG_OUTPUT"
hdiutil verify "$SAYTILE_DMG_OUTPUT"
shasum -a 256 "$SAYTILE_DMG_OUTPUT" > "$SAYTILE_DMG_OUTPUT.sha256"
printf 'Packaged %s\n' "$SAYTILE_DMG_OUTPUT"
