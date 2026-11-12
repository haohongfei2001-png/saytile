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
run_tests() {
  swift test --scratch-path "$SAYTILE_TEST_SCRATCH" ${SAYTILE_TEST_FLAGS[@]+"${SAYTILE_TEST_FLAGS[@]}"} "$@"
}

if (( $# > 0 )); then
  # Keep explicit filters/options available for targeted diagnostics.
  run_tests "$@" 2>&1 | tee "$SAYTILE_TEST_LOG"
else
  # Frame sampling and the app's display link run on the same main actor.
  # Keep unrelated concurrent tests out of the measurement process.
  frame_suite=LiveTailViewportTests
  echo "== Isolated native viewport frames ==" | tee "$SAYTILE_TEST_LOG"
  run_tests --filter "$frame_suite" 2>&1 | tee -a "$SAYTILE_TEST_LOG"
  echo "== Remaining Swift suites ==" | tee -a "$SAYTILE_TEST_LOG"
  run_tests --skip-build --skip "$frame_suite" 2>&1 | tee -a "$SAYTILE_TEST_LOG"
fi
