#!/bin/bash
set -euo pipefail
cd /private/tmp/saytile-release-101
app=/private/tmp/saytile-release101-public/Saytile.app
dmg=/Users/hhf/Documents/GitHub/saytile/dist/1.0.1/Saytile-1.0.1-arm64.dmg
identity=92B7E50A1D43D247EA7EA19A31DCA3E407435A42
test ! -e "$dmg"
test "$(plutil -extract SaytileSourceRevision raw "$app/Contents/Info.plist")" = 73ad857442964437929819ba9965f6bcfdcefd27
test "$(plutil -extract SaytileSourceDirty raw "$app/Contents/Info.plist")" = false
codesign --verify --deep --strict "$app"
stage=$(mktemp -d /tmp/saytile-release101-dmg.XXXXXX)
trap 'rm -rf "$stage"' EXIT
cp -cR "$app" "$stage/Saytile.app"
ln -s /Applications "$stage/Applications"
cp docs/V1-INSTALL.md "$stage/安装与使用.txt"
cmp "$app/Contents/MacOS/Saytile" "$stage/Saytile.app/Contents/MacOS/Saytile"
mkdir -p "$(dirname "$dmg")"
hdiutil create -volname 'Saytile 1.0.1' -srcfolder "$stage" -format UDZO "$dmg"
codesign --force --timestamp --sign "$identity" "$dmg"
codesign --verify --strict "$dmg"
hdiutil verify "$dmg"
(cd "$(dirname "$dmg")" && shasum -a 256 Saytile-1.0.1-arm64.dmg > SHA256SUMS.txt)
