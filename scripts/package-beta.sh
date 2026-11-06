#!/bin/bash
# Historical entry point retained; packaging/VERSION names the current prerelease.
set -euo pipefail
cd "$(dirname "$0")/.."
SAYTILE_STAGE="$(mktemp -d /tmp/saytile-package.XXXXXX)"
trap 'rm -rf "$SAYTILE_STAGE"' EXIT
SAYTILE_APP_OUTPUT="$SAYTILE_STAGE/Saytile.app" scripts/build-app.sh release
SAYTILE_VERSION="$(cat packaging/VERSION)"
SAYTILE_DMG="Saytile-$SAYTILE_VERSION-arm64.dmg"
ln -s /Applications "$SAYTILE_STAGE/Applications"
cp docs/V1-INSTALL.md "$SAYTILE_STAGE/安装与使用.txt"
mkdir -p dist
hdiutil create -volname "Saytile $SAYTILE_VERSION" -srcfolder "$SAYTILE_STAGE" -ov -format UDZO "dist/$SAYTILE_DMG"
hdiutil verify "dist/$SAYTILE_DMG"
(cd dist && shasum -a 256 "$SAYTILE_DMG" > SHA256SUMS.txt)
printf 'Packaged dist/%s\n' "$SAYTILE_DMG"
