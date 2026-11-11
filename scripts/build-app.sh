#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
SAYTILE_BUILD_SCRATCH="${SAYTILE_BUILD_SCRATCH:-/tmp/saytile-build}"
SAYTILE_BUILD_COMMAND=(swift build --scratch-path "$SAYTILE_BUILD_SCRATCH" -c "$configuration")
if [[ "${SAYTILE_SWIFT_DISABLE_SANDBOX:-0}" == 1 ]]; then SAYTILE_BUILD_COMMAND+=(--disable-sandbox); fi
version=$(cat packaging/VERSION)
if [[ "$version" == *-integrated.* ]]; then
  scripts/prepare-updater.sh
  SAYTILE_BUILD_COMMAND+=(-Xswiftc -F -Xswiftc "$PWD/.build/sparkle" -Xlinker -F -Xlinker "$PWD/.build/sparkle" -Xlinker -rpath -Xlinker @executable_path/../Frameworks)
fi
"${SAYTILE_BUILD_COMMAND[@]}"
bin_dir="$("${SAYTILE_BUILD_COMMAND[@]}" --show-bin-path)"
app="${SAYTILE_APP_OUTPUT:-$PWD/dist/Saytile.app}"
SAYTILE_BUILD_STAGE="$(mktemp -d /tmp/saytile-bundle.XXXXXX)"
trap 'rm -rf "$SAYTILE_BUILD_STAGE"' EXIT
bundle="$SAYTILE_BUILD_STAGE/Saytile.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$bin_dir/Saytile" "$bundle/Contents/MacOS/Saytile"
swift scripts/make-icon.swift "$SAYTILE_BUILD_STAGE/Saytile.iconset"
if ! iconutil -c icns "$SAYTILE_BUILD_STAGE/Saytile.iconset" -o "$bundle/Contents/Resources/Saytile.icns"; then
  python3 scripts/encode-iconset.py "$SAYTILE_BUILD_STAGE/Saytile.iconset" "$bundle/Contents/Resources/Saytile.icns"
fi
cp -R Sources/SaytileKit/Resources/LocalASR "$bundle/Contents/Resources/"
if [[ "$version" == *-local-asr.* || "$version" == *-integrated.* ]]; then
  scripts/build-local-runtime.sh
  mkdir -p "$bundle/Contents/Helpers" "$bundle/Contents/Frameworks"
  cp .build/local-asr/runtime/{SaytileSherpa,SaytileModelWorker} "$bundle/Contents/Helpers/"
  cp .build/local-asr/runtime/*.dylib "$bundle/Contents/Frameworks/"
  cp .build/local-asr/runtime/mlx.metallib "$bundle/Contents/Resources/default.metallib"
  install_name_tool -add_rpath @executable_path/../Frameworks "$bundle/Contents/Helpers/SaytileSherpa"
  cp -R .build/local-asr/runtime-licenses "$bundle/Contents/Resources/LocalASRLicenses"
  for child in "$bundle/Contents/Frameworks/"*.dylib "$bundle/Contents/Helpers/"{SaytileSherpa,SaytileModelWorker}; do
    codesign --force --sign "${SAYTILE_SIGN_IDENTITY:--}" --timestamp=none "$child"
  done
fi
cp Sources/SaytileKit/Resources/ConnectionSample.pcm "$bundle/Contents/Resources/ConnectionSample.pcm"
cp THIRD_PARTY_NOTICES.md "$bundle/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp Sources/CAudio/WEBRTC-LICENSE.txt "$bundle/Contents/Resources/WEBRTC-LICENSE.txt"
cp packaging/Info.plist "$bundle/Contents/Info.plist"
if [[ "$version" == *-integrated.* ]]; then
  ditto .build/sparkle/Sparkle.framework "$bundle/Contents/Frameworks/Sparkle.framework"
  cp .build/sparkle/LICENSE "$bundle/Contents/Resources/SPARKLE-LICENSE.txt"
  if [[ -n "${SAYTILE_UPDATE_FEED:-}${SAYTILE_UPDATE_PUBLIC_KEY:-}" ]]; then
    python3 scripts/configure-update-feed.py "$bundle/Contents/Info.plist"
  fi
fi
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
