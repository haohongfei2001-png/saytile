#!/bin/bash
# Build dependency only. Consumers run the embedded framework.
set -euo pipefail
cd "$(dirname "$0")/.."
version=2.10.1
digest=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
dir=.build/sparkle
mkdir -p .build
archive=.build/Sparkle-$version.tar.xz
if ! echo "$digest  $archive" | shasum -a 256 -c - >/dev/null 2>&1; then
    curl --fail --silent --show-error --location --retry 2 --max-time 240 \
        "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$archive.part"
    echo "$digest  $archive.part" | shasum -a 256 -c -
    mv "$archive.part" "$archive"
fi
mkdir -p "$dir"
tar xf "$archive" -C "$dir"
