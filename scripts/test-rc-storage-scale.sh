#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SAYTILE_STORAGE_SCRATCH=/tmp/saytile-rc-storage
mkdir -p "$SAYTILE_STORAGE_SCRATCH" evidence/rc
swiftc -O -swift-version 6 -parse-as-library -I Sources/CSQLite \
  Sources/SaytileKit/Models.swift Sources/SaytileKit/Store.swift \
  Sources/SaytileKit/StoreSQLite.swift Sources/SaytileKit/StoreLock.swift \
  tests/fixtures/StoreScaleProbe.swift -o "$SAYTILE_STORAGE_SCRATCH/scale-probe"
SAYTILE_SCALE_FIXTURE="$(mktemp -d "$SAYTILE_STORAGE_SCRATCH/scale.XXXXXX")"
trap 'rm -rf "$SAYTILE_SCALE_FIXTURE"' EXIT
/usr/bin/time -l "$SAYTILE_STORAGE_SCRATCH/scale-probe" "$SAYTILE_SCALE_FIXTURE" 100000 2> evidence/rc/storage-scale-resources.log | tee evidence/rc/storage-scale.json
