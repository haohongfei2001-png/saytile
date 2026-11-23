#!/bin/bash
# Developer ID distribution only. Sign inside-out, preserving the pinned model worker when already valid.
set -euo pipefail
app=${1:?staged app required}
identity=${2:?Developer ID Application certificate SHA-1 required}
[[ "$identity" =~ ^[[:xdigit:]]{40}$ && -d "$app/Contents/Helpers" ]]
cert="anchor apple generic and certificate leaf = H\"$identity\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
sign() { codesign --force --options runtime --timestamp --sign "$identity" "$@"; }
for child in "$app/Contents/Frameworks/"*.dylib "$app/Contents/Helpers/SaytileSherpa" "$app/Contents/Helpers/SaytileModelWorker"; do
  signature=$(codesign -dv --verbose=4 "$child" 2>&1 || true)
  if ! codesign --verify -R="$cert" "$child" 2>/dev/null || [[ "$signature" != *"(runtime)"* || "$signature" != *"Timestamp="* ]]; then
    sign "$child"
  fi
done
framework="$app/Contents/Frameworks/Sparkle.framework"
version="$framework/Versions/B"
sign "$version/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$version/XPCServices/Downloader.xpc"
sign "$version/Autoupdate"
sign "$version/Updater.app"
sign "$framework"
sign --entitlements "$(dirname "$0")/audio-input.plist" "$app"
codesign --verify --deep --strict -R="$cert" "$app"
