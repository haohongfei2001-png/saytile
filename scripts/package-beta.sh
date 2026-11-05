#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh release
SAYTILE_STAGE="$(mktemp -d /tmp/saytile-package.XXXXXX)"
trap 'rm -rf "$SAYTILE_STAGE"' EXIT
ditto --norsrc dist/Saytile.app "$SAYTILE_STAGE/Saytile.app"
ln -s /Applications "$SAYTILE_STAGE/Applications"
cp docs/V1-INSTALL.md "$SAYTILE_STAGE/安装与使用.txt"
xattr -cr "$SAYTILE_STAGE/Saytile.app"
hdiutil create -volname 'Saytile V1 Beta' -srcfolder "$SAYTILE_STAGE" -ov -format UDZO dist/Saytile-1.0.0-beta.1-arm64.dmg
hdiutil verify dist/Saytile-1.0.0-beta.1-arm64.dmg
shasum -a 256 dist/Saytile-1.0.0-beta.1-arm64.dmg > dist/SHA256SUMS.txt
