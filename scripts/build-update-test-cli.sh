#!/bin/bash
# The upstream engineering CLI is compiled against the same pinned framework as Saytile.
set -euo pipefail
cd "$(dirname "$0")/.."
revision=ab7d71291238df6e0492143b120c9b696a35f603
dest=.build/integration/sparkle-cli-source
mkdir -p "$dest"
for file in main.m SPUCommandLineDriver.h SPUCommandLineDriver.m SPUCommandLineUserDriver.h SPUCommandLineUserDriver.m; do
    curl -fsSL --retry 2 "https://raw.githubusercontent.com/sparkle-project/Sparkle/$revision/sparkle-cli/$file" -o "$dest/$file"
done
clang -fobjc-arc -fmodules -DSPU_OBJC_DIRECT_MEMBERS= -DSPU_OBJC_DIRECT= -F .build/sparkle \
    -framework Foundation -framework AppKit -framework Sparkle -Wl,-rpath,"$PWD/.build/sparkle" \
    "$dest/"*.m -o .build/integration/sparkle-cli
