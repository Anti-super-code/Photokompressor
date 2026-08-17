#!/bin/bash
# Dev convenience: build the SwiftPM package and drop libvips.42.dylib next to
# the built products, since it's loaded via @loader_path (its own install
# name), not an rpath — this only matters for `swift build`/`swift test`
# during development. The packaged .app embeds it in Contents/MacOS the same
# way at release time (see build/package.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
swift build -c "$CONFIG"

for dir in ".build/debug" ".build/release" ".build/arm64-apple-macosx/debug" ".build/arm64-apple-macosx/release"; do
    if [ -d "$dir" ]; then
        cp -f Vendor/libvips/lib/libvips.42.dylib "$dir/" 2>/dev/null || true
    fi
done
