#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
SAYTILE_BUILD_SCRATCH="${SAYTILE_BUILD_SCRATCH:-/tmp/saytile-build}"
swift build --scratch-path "$SAYTILE_BUILD_SCRATCH" -c "$configuration"
bin_dir="$(swift build --scratch-path "$SAYTILE_BUILD_SCRATCH" -c "$configuration" --show-bin-path)"
app="${SAYTILE_APP_OUTPUT:-$PWD/dist/Saytile.app}"
SAYTILE_BUILD_STAGE="$(mktemp -d /tmp/saytile-bundle.XXXXXX)"
trap 'rm -rf "$SAYTILE_BUILD_STAGE"' EXIT
bundle="$SAYTILE_BUILD_STAGE/Saytile.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$bin_dir/Saytile" "$bundle/Contents/MacOS/Saytile"
swift scripts/make-icon.swift "$SAYTILE_BUILD_STAGE/Saytile.iconset"
iconutil -c icns "$SAYTILE_BUILD_STAGE/Saytile.iconset" -o "$bundle/Contents/Resources/Saytile.icns"
cp THIRD_PARTY_NOTICES.md "$bundle/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp Sources/CAudio/WEBRTC-LICENSE.txt "$bundle/Contents/Resources/WEBRTC-LICENSE.txt"
cp packaging/Info.plist "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SaytileSourceRevision string $(git rev-parse HEAD)" "$bundle/Contents/Info.plist"
SAYTILE_SOURCE_DIRTY=false
if ! git diff --quiet HEAD -- Sources Package.swift packaging scripts/build-app.sh; then SAYTILE_SOURCE_DIRTY=true; fi
if [[ -n "$(git ls-files --others --exclude-standard Sources packaging)" ]]; then SAYTILE_SOURCE_DIRTY=true; fi
/usr/libexec/PlistBuddy -c "Add :SaytileSourceDirty bool $SAYTILE_SOURCE_DIRTY" "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SaytileReleaseVersion string $(cat packaging/VERSION)" "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$bundle/Contents/Info.plist"
xattr -cr "$bundle"
codesign --force --sign "${SAYTILE_SIGN_IDENTITY:--}" --timestamp=none "$bundle"
codesign --verify --strict "$bundle"
plutil -lint "$bundle/Contents/Info.plist"
# The destination is an explicitly chosen build artifact. Never mix old bundle resources.
if [[ -e "$app" ]]; then
  if [[ "$app" != "$PWD/dist/Saytile.app" && "$app" != /tmp/saytile-*/* ]]; then
    printf 'Refusing to replace an existing non-build output: %s\n' "$app" >&2
    exit 64
  fi
  rm -rf "$app"
fi
mkdir -p "$(dirname "$app")"
ditto --norsrc "$bundle" "$app"
codesign --verify --strict "$app"
printf 'Built %s\n' "$app"
