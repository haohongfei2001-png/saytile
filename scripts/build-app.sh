#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
SAYTILE_BUILD_SCRATCH="${SAYTILE_BUILD_SCRATCH:-/tmp/saytile-build}"
SAYTILE_BUILD_COMMAND=(swift build --scratch-path "$SAYTILE_BUILD_SCRATCH" -c "$configuration")
if [[ "${SAYTILE_SWIFT_DISABLE_SANDBOX:-0}" == 1 ]]; then SAYTILE_BUILD_COMMAND+=(--disable-sandbox); fi
version=$(cat packaging/VERSION)
icloud_candidate="${SAYTILE_ICLOUD_CANDIDATE:-0}"
icloud_profile="${SAYTILE_ICLOUD_DEVELOPMENT_PROFILE:-}"
if [[ -n "$icloud_profile" && "$icloud_candidate" != 1 ]]; then
  echo "An iCloud development profile requires the isolated iCloud candidate." >&2
  exit 64
fi
if [[ "$icloud_candidate" == 1 && "${SAYTILE_MANDARIN_CANDIDATE:-0}" == 1 ]]; then
  echo "Choose one candidate identity for this build." >&2
  exit 64
fi
if [[ "$icloud_candidate" == 1 && -n "${SAYTILE_UPDATE_FEED:-}${SAYTILE_UPDATE_PUBLIC_KEY:-}" ]]; then
  echo "The isolated iCloud development build has no distribution update feed." >&2
  exit 64
fi
for old_identity in SAYTILE_PERSONAL_EXPERIENCE SAYTILE_DESIGN_EXPERIENCE SAYTILE_SHARED_VOICE_PREVIEW; do
  if [[ "${!old_identity:-0}" == 1 ]]; then
    echo "There is one Saytile application. For tests, launch it with an isolated --data-directory." >&2
    exit 64
  fi
done
scripts/prepare-updater.sh
SAYTILE_BUILD_COMMAND+=(-Xswiftc -F -Xswiftc "$PWD/.build/sparkle" -Xlinker -F -Xlinker "$PWD/.build/sparkle" -Xlinker -rpath -Xlinker @executable_path/../Frameworks)
"${SAYTILE_BUILD_COMMAND[@]}"
bin_dir="$("${SAYTILE_BUILD_COMMAND[@]}" --show-bin-path)"
default_app="$PWD/dist/Saytile.app"
if [[ "$icloud_candidate" == 1 ]]; then default_app="$PWD/dist/Saytile iCloud Candidate.app"; fi
app="${SAYTILE_APP_OUTPUT:-$default_app}"
if [[ "$icloud_candidate" == 1 && "$app" == "$PWD/dist/Saytile.app" ]]; then exit 64; fi
SAYTILE_BUILD_STAGE="$(mktemp -d /tmp/saytile-bundle.XXXXXX)"
trap 'rm -rf "$SAYTILE_BUILD_STAGE"' EXIT
bundle="$SAYTILE_BUILD_STAGE/Saytile.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$bin_dir/Saytile" "$bundle/Contents/MacOS/Saytile"
# Native derivatives of the approved artwork, not its rectangular presentation canvas.
icon_source="packaging/brand/SaytilePlate.png"
cp Sources/SaytileApp/Resources/SaytileBrandMark.png "$bundle/Contents/Resources/"
mkdir "$SAYTILE_BUILD_STAGE/Saytile.iconset"
for size in 16 32 128 256 512; do
  for scale in 1 2; do
    pixels=$((size * scale))
    suffix=""
    if [[ "$scale" == 2 ]]; then suffix="@2x"; fi
    sips -s format png -z "$pixels" "$pixels" "$icon_source" --out "$SAYTILE_BUILD_STAGE/Saytile.iconset/icon_${size}x${size}${suffix}.png" >/dev/null
  done
done
if ! iconutil -c icns "$SAYTILE_BUILD_STAGE/Saytile.iconset" -o "$bundle/Contents/Resources/Saytile.icns"; then
  python3 scripts/encode-iconset.py "$SAYTILE_BUILD_STAGE/Saytile.iconset" "$bundle/Contents/Resources/Saytile.icns"
fi
cp -R Sources/SaytileKit/Resources/LocalASR "$bundle/Contents/Resources/"
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
cp Sources/SaytileKit/Resources/ConnectionSample.pcm "$bundle/Contents/Resources/ConnectionSample.pcm"
cp THIRD_PARTY_NOTICES.md "$bundle/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp Sources/CAudio/WEBRTC-LICENSE.txt "$bundle/Contents/Resources/WEBRTC-LICENSE.txt"
cp packaging/Info.plist "$bundle/Contents/Info.plist"
if [[ "${SAYTILE_MANDARIN_CANDIDATE:-0}" == 1 ]]; then
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier app.saytile.mac.mandarin-candidate' "$bundle/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Saytile 中文识别候选' "$bundle/Contents/Info.plist"
elif [[ "$icloud_candidate" == 1 ]]; then
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier app.saytile.mac.icloud-candidate' "$bundle/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Saytile iCloud 候选' "$bundle/Contents/Info.plist"
fi
ditto .build/sparkle/Sparkle.framework "$bundle/Contents/Frameworks/Sparkle.framework"
cp .build/sparkle/LICENSE "$bundle/Contents/Resources/SPARKLE-LICENSE.txt"
if [[ -n "${SAYTILE_UPDATE_FEED:-}${SAYTILE_UPDATE_PUBLIC_KEY:-}" ]]; then
  python3 scripts/configure-update-feed.py "$bundle/Contents/Info.plist"
fi
/usr/libexec/PlistBuddy -c "Add :SaytileSourceRevision string $(git rev-parse HEAD)" "$bundle/Contents/Info.plist"
SAYTILE_SOURCE_DIRTY=false
if ! git diff --quiet HEAD -- Sources Package.swift native/LocalASR packaging scripts/build-app.sh scripts/build-local-runtime.sh scripts/prepare-local-runtime.sh; then SAYTILE_SOURCE_DIRTY=true; fi
if [[ -n "$(git ls-files --others --exclude-standard Sources native/LocalASR packaging)" ]]; then SAYTILE_SOURCE_DIRTY=true; fi
/usr/libexec/PlistBuddy -c "Add :SaytileSourceDirty bool $SAYTILE_SOURCE_DIRTY" "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $version" "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SaytileReleaseVersion string $version" "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$bundle/Contents/Info.plist"
xattr -cr "$bundle"
if [[ -n "$icloud_profile" ]]; then
  scripts/sign-icloud-development.sh "$bundle" "$icloud_profile" "${SAYTILE_SIGN_IDENTITY:-}"
else
  codesign --force --sign "${SAYTILE_SIGN_IDENTITY:--}" --timestamp=none "$bundle"
fi
codesign --verify --strict "$bundle"
plutil -lint "$bundle/Contents/Info.plist"
# The destination is an explicitly chosen build artifact. Never mix old bundle resources.
if [[ -e "$app" ]]; then
  if [[ "$app" != "$default_app" && "$app" != /tmp/saytile-*/* ]]; then
    printf 'Refusing to replace an existing non-build output: %s\n' "$app" >&2
    exit 64
  fi
  rm -rf "$app"
fi
mkdir -p "$(dirname "$app")"
ditto --norsrc "$bundle" "$app"
codesign --verify --strict "$app"
printf 'Built %s\n' "$app"
