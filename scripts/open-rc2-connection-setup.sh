#!/bin/bash
# Run manually after reviewing the candidate. No install, microphone, model call or key export.
set -euo pipefail
cd "$(dirname "$0")/.."
SAYTILE_SETUP_REPOSITORY="$PWD"
SAYTILE_SETUP_APP="${1:-$SAYTILE_SETUP_REPOSITORY/dist/Saytile.app}"
python3 - "$SAYTILE_SETUP_REPOSITORY" "$SAYTILE_SETUP_APP" <<'PY'
import pathlib,plistlib,sys
repo=pathlib.Path(sys.argv[1]);app=pathlib.Path(sys.argv[2])
if not app.is_absolute() or not app.resolve().is_relative_to((repo/'dist').resolve()):
    raise SystemExit('Provide an absolute candidate app path inside this repository dist/.')
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
if not info.get('SaytileReleaseVersion','').startswith('1.0.0-rc.2') or info.get('SaytileSourceDirty') is not False:
    raise SystemExit('Use the clean RC2 candidate, not the installed RC1 or a dirty development build.')
if not (app/'Contents/MacOS/Saytile').is_file(): raise SystemExit('Candidate executable missing.')
PY
if [[ -L "$SAYTILE_SETUP_REPOSITORY/dist" ]]; then
  printf 'Refusing a symbolic-link dist directory.\n' >&2
  exit 64
fi
SAYTILE_SETUP_DIRECTORY="$(mktemp -d "$SAYTILE_SETUP_REPOSITORY/dist/connection-setup.XXXXXX")"
SAYTILE_SETUP_OUTPUT="$SAYTILE_SETUP_DIRECTORY/recognition-config.json"
printf 'Setup only; RC1 remains installed. Non-secret configuration path: %s\n' "$SAYTILE_SETUP_OUTPUT"
"$SAYTILE_SETUP_APP/Contents/MacOS/Saytile" --connection-setup \
  --data-directory "$SAYTILE_SETUP_DIRECTORY" --connection-output "$SAYTILE_SETUP_OUTPUT"
if [[ -f "$SAYTILE_SETUP_OUTPUT" ]]; then
  printf 'Connection settings saved. No provider call was made. Configuration: %s\n' "$SAYTILE_SETUP_OUTPUT"
else
  printf 'Setup closed without exporting configuration. Keys explicitly saved remain in Keychain.\n'
fi
