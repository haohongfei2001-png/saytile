#!/bin/bash
# Called on the build-app staging bundle. Restricted entitlements are derived
# from the developer's explicit macOS development profile for this candidate.
set -euo pipefail
app="$1"
profile="$2"
identity="$3"
if [[ ! -f "$profile" || ! "$identity" =~ ^[a-fA-F0-9]{40}$ ]]; then
  echo "A macOS development profile and its signing identity fingerprint are required." >&2
  exit 64
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" != app.saytile.mac.icloud-candidate ]]; then
  echo "This signing flow is limited to the isolated iCloud development candidate." >&2
  exit 64
fi
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
security cms -D -i "$profile" -o "$stage/profile.plist"
python3 - "$stage/profile.plist" "$stage/entitlements.plist" "$identity" <<'PY'
import datetime
import hashlib
import plistlib
import sys
from pathlib import Path

profile_path, output, identity = sys.argv[1:]
p = plistlib.loads(Path(profile_path).read_bytes())
e = p["Entitlements"]
bundle_id = "app.saytile.mac.icloud-candidate"
teams = p["TeamIdentifier"]
app_ids = {prefix + "." + bundle_id for prefix in p["ApplicationIdentifierPrefix"]}
identifier = e.get("com.apple.application-identifier")
team = e.get("com.apple.developer.team-identifier")
environment = e.get("com.apple.developer.icloud-container-environment")
services = e.get("com.apple.developer.icloud-services", [])
containers = e.get("com.apple.developer.icloud-container-identifiers", [])
container = "iCloud.app.saytile.archive"
certs = {hashlib.sha1(der).hexdigest() for der in p["DeveloperCertificates"]}
def permits(values, required):
    if isinstance(values, str):
        values = [values]
    return required in values or "*" in values

if not (identifier in app_ids and team in teams and identity.lower() in certs
        and "OSX" in p.get("Platform", []) and p.get("ProvisionedDevices")
        and p["ExpirationDate"] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
        and permits(environment or [], "Development") and permits(services, "CloudKit")
        and container in containers):
    sys.exit("Profile must authorize this identity, macOS candidate ID and Development CloudKit container.")
entitlements = {
    "com.apple.application-identifier": identifier,
    "com.apple.developer.team-identifier": team,
    "com.apple.developer.icloud-container-identifiers": [container],
    "com.apple.developer.icloud-container-environment": "Development",
    "com.apple.developer.icloud-services": ["CloudKit"],
    "com.apple.security.device.audio-input": True,
}
Path(output).write_bytes(plistlib.dumps(entitlements))
PY
cp "$profile" "$app/Contents/embedded.provisionprofile"
# Hardened library validation requires embedded, in-process frameworks to
# carry the same Team ID as the app. Sparkle's separately launched helpers
# keep the signatures supplied by its distribution.
framework="$app/Contents/Frameworks/Sparkle.framework"
if [[ -d "$framework" ]]; then
  codesign --force --options runtime --timestamp=none --sign "$identity" "$framework"
fi
codesign --force --options runtime --timestamp=none --sign "$identity" --entitlements "$stage/entitlements.plist" "$app"
codesign --verify --deep --strict "$app"
