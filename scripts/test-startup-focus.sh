#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SAYTILE_FOCUS_DIR="$(mktemp -d /tmp/saytile-focus-probe.XXXXXX)"
trap 'rm -rf "$SAYTILE_FOCUS_DIR"' EXIT
swiftc -swift-version 6 -parse-as-library tests/fixtures/StartupFocusProbe.swift -o "$SAYTILE_FOCUS_DIR/probe"
"$SAYTILE_FOCUS_DIR/probe" "$PWD/dist/Saytile.app/Contents/MacOS/Saytile" "$SAYTILE_FOCUS_DIR/data" | tee evidence/native/startup-focus.log
