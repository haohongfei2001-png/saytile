#!/bin/bash
# Run the real Swift Testing suite with Command Line Tools or Xcode.
# Keep generated signed test bundles off cloud-backed workspace volumes.
set -euo pipefail
cd "$(dirname "$0")/.."
SAYTILE_SWIFTC="$(xcrun --find swiftc)"
SAYTILE_TOOLCHAIN_USR="$(dirname "$(dirname "$SAYTILE_SWIFTC")")"
SAYTILE_TEST_PLUGIN="$SAYTILE_TOOLCHAIN_USR/lib/swift/host/plugins/testing/libTestingMacros.dylib"
SAYTILE_TEST_SCRATCH="${SAYTILE_TEST_SCRATCH:-/tmp/saytile-v1-native-tests}"
SAYTILE_TEST_FLAGS=()
if [[ -f "$SAYTILE_TEST_PLUGIN" ]]; then
  SAYTILE_TEST_FLAGS=(-Xswiftc -load-plugin-library -Xswiftc "$SAYTILE_TEST_PLUGIN")
fi
SAYTILE_TEST_LOG="${SAYTILE_TEST_LOG:-evidence/native-tests.log}"
mkdir -p "$(dirname "$SAYTILE_TEST_LOG")"
# Default Swift Build supplies Testing.framework and the correct test runner.
# Do not force --build-system native: it omits framework discovery in CLT 6.4.
swift test --scratch-path "$SAYTILE_TEST_SCRATCH" "${SAYTILE_TEST_FLAGS[@]}" "$@" 2>&1 | tee "$SAYTILE_TEST_LOG"
