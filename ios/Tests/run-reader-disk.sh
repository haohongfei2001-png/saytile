#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
stage="$(mktemp -d "${TMPDIR:-/tmp}/saytile-reader-disk-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path "$stage/modules" \
  Sources/SaytileKit/RevisionOrigin.swift Sources/SaytileKit/PrivateArchiveManifest.swift \
  Sources/SaytileKit/ArchiveCloudRecord.swift ios/Reader/ReaderSource.swift ios/Tests/ReaderDiskProbe.swift \
  -o "$stage/ReaderDiskProbe"
"$stage/ReaderDiskProbe"
