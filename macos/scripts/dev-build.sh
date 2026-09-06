#!/bin/bash
# Dev convenience: build the SwiftPM package and drop libvips.42.dylib next to
# the built products, since it's loaded via @loader_path (its own install
# name), not an rpath — this only matters for `swift build`/`swift test`
# during development. The packaged .app embeds it in Contents/MacOS the same
# way at release time (see build/package.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-build}"   # build | test
CONFIG="${2:-debug}"

if [ "$MODE" = "test" ]; then
    swift build --build-tests -c "$CONFIG"
else
    swift build -c "$CONFIG"
fi

DYLIB="Vendor/libvips/lib/libvips.42.dylib"
for dir in ".build/debug" ".build/release" ".build/arm64-apple-macosx/$CONFIG"; do
    [ -d "$dir" ] && cp -f "$DYLIB" "$dir/" 2>/dev/null || true
done
for bundle in .build/arm64-apple-macosx/"$CONFIG"/*.xctest; do
    [ -d "$bundle/Contents/MacOS" ] && cp -f "$DYLIB" "$bundle/Contents/MacOS/" 2>/dev/null || true
done

if [ "$MODE" = "test" ]; then
    swift test -c "$CONFIG" --skip-build
fi
