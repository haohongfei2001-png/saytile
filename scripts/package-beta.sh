#!/bin/bash
# Historical entry point retained; packaging/VERSION names the current prerelease.
set -euo pipefail
cd "$(dirname "$0")/.."
SAYTILE_STAGE="$(mktemp -d /tmp/saytile-package.XXXXXX)"
trap 'rm -rf "$SAYTILE_STAGE"' EXIT
SAYTILE_APP_OUTPUT="$SAYTILE_STAGE/Saytile.app" scripts/build-app.sh release
SAYTILE_VERSION="$(cat packaging/VERSION)"
SAYTILE_DMG="Saytile-$SAYTILE_VERSION-arm64.dmg"
SAYTILE_DMG_OUTPUT="${SAYTILE_DMG_OUTPUT:-dist/$SAYTILE_DMG}"
ln -s /Applications "$SAYTILE_STAGE/Applications"
cp docs/V1-INSTALL.md "$SAYTILE_STAGE/安装与使用.txt"
mkdir -p "$(dirname "$SAYTILE_DMG_OUTPUT")"
if [[ -e "$SAYTILE_DMG_OUTPUT" ]]; then
  printf 'Refusing to replace an existing DMG candidate: %s\n' "$SAYTILE_DMG_OUTPUT" >&2
  exit 64
fi
hdiutil create -volname "Saytile $SAYTILE_VERSION" -srcfolder "$SAYTILE_STAGE" -format UDZO "$SAYTILE_DMG_OUTPUT"
hdiutil verify "$SAYTILE_DMG_OUTPUT"
shasum -a 256 "$SAYTILE_DMG_OUTPUT" > "$SAYTILE_DMG_OUTPUT.sha256"
printf 'Packaged %s\n' "$SAYTILE_DMG_OUTPUT"
