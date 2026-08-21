#!/bin/bash
# Builds the macOS download that goes on the website: a self-contained
# Photokompressor.app (Apple Silicon only), ad-hoc signed, in a .dmg,
# with a SHA-256 beside it — the macOS counterpart of package.ps1.
#
#   bash build/package-mac.sh
#   bash build/package-mac.sh --skip-tests   # only when you already ran them
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACOS_DIR="$REPO/macos"
DIST="$REPO/dist-mac"

SKIP_TESTS=0
for arg in "$@"; do
    [ "$arg" = "--skip-tests" ] && SKIP_TESTS=1
done

# Kept in step with the Windows build's <Version> in Photokompressor.csproj.
VERSION="1.0.0"
NAME="Photokompressor-${VERSION}-mac-arm64"
STAGE="$DIST/stage"
APP="$STAGE/Photokompressor.app"
DMG="$DIST/$NAME.dmg"

echo "Packaging Photokompressor $VERSION (macOS, arm64)"

cd "$MACOS_DIR"

if [ "$SKIP_TESTS" -eq 0 ]; then
    echo "-> tests"
    bash scripts/dev-build.sh test
fi

echo "-> build (release)"
swift build -c release --product Photokompressor
swift build -c release --product photokompressor-cli

RELEASE_DIR="$MACOS_DIR/.build/release"

echo "-> assemble app bundle"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$RELEASE_DIR/Photokompressor" "$APP/Contents/MacOS/Photokompressor"
# SwiftPM's generated Bundle.module accessor resolves its resource bundle
# against Bundle.main.bundleURL, which for a packaged app is the .app's own
# root — outside Contents, a location codesign won't seal (confirmed via
# `spctl --assess`: a bundle placed there makes the whole app fail Gatekeeper
# assessment once quarantined, i.e. exactly the state a downloaded DMG is in).
# Its only other candidate is a hardcoded absolute path into *this build
# machine's* .build directory. So Theme.swift's FontRegistration checks
# Bundle.main first and only touches Bundle.module (and its fatalError) as a
# `swift run`-only fallback — meaning the packaged app must carry its fonts
# in the ordinary Contents/Resources, not SwiftPM's generated bundle.
if [ -d "$RELEASE_DIR/Photokompressor_Photokompressor.bundle/Fonts" ]; then
    cp -R "$RELEASE_DIR/Photokompressor_Photokompressor.bundle/Fonts" "$APP/Contents/Resources/Fonts"
fi
# libvips.42.dylib's install name is @loader_path/libvips.42.dylib, so it
# has to sit next to the executable that loads it too.
cp "$MACOS_DIR/Vendor/libvips/lib/libvips.42.dylib" "$APP/Contents/MacOS/libvips.42.dylib"

cp "$MACOS_DIR/Resources/AppIcon/Photokompressor.icns" "$APP/Contents/Resources/Photokompressor.icns"

sed "s/__VERSION__/$VERSION/g" "$MACOS_DIR/Resources/Info.plist.template" > "$APP/Contents/Info.plist"

echo "-> licences and read-me"
cp "$REPO/LICENSE" "$STAGE/LICENSE"
cp "$MACOS_DIR/Vendor/libvips/THIRD-PARTY-NOTICES.md" "$STAGE/THIRD-PARTY-NOTICES-libvips.md"

cat > "$STAGE/READ-ME-FIRST.txt" << EOF
Photokompressor $VERSION for macOS
===================================

1. Drag Photokompressor.app to Applications (or run it from wherever you
   put it — it doesn't need to live in /Applications).

2. Because this build isn't notarized by Apple, the first time you open it
   Gatekeeper will refuse with "Apple could not verify... is free of
   malware." Right-click (or Control-click) Photokompressor.app, choose
   Open, then click Open again in the dialog. You only need to do this
   once.

3. Click the round gear button, then switch on "Right-click menu". You can
   now right-click any photo in Finder and choose Compress with
   Photokompressor from Quick Actions.

To uninstall: switch "Right-click menu" back off, delete Photokompressor.app,
and delete ~/Library/Application Support/Photokompressor.

Use at your own risk - see LICENSE and the disclaimer in the main README on
the website.
Source: https://github.com/Anti-super-code/Photokompressor
EOF

echo "-> codesign (ad-hoc)"
# Sign the nested dylib before the outer app, same order a real --deep sign
# would use. The fonts need no separate signing step now that they're
# ordinary files under Contents/Resources rather than a nested bundle.
codesign --force --sign - "$APP/Contents/MacOS/libvips.42.dylib"
codesign --force --sign - "$APP"
codesign --verify --strict --verbose "$APP" 2>&1 | tail -5

echo "-> dmg"
mkdir -p "$STAGE-dmg"
cp -R "$APP" "$STAGE-dmg/"
ln -s /Applications "$STAGE-dmg/Applications"
cp "$STAGE/READ-ME-FIRST.txt" "$STAGE-dmg/"
cp "$STAGE/LICENSE" "$STAGE-dmg/"
cp "$STAGE/THIRD-PARTY-NOTICES-libvips.md" "$STAGE-dmg/"

rm -f "$DMG"
hdiutil create -volname "Photokompressor $VERSION" -srcfolder "$STAGE-dmg" -ov -format UDZO "$DMG" -quiet

HASH=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo "$HASH  $NAME.dmg" > "$DMG.sha256"

DMG_MB=$(du -m "$DMG" | awk '{print $1}')

echo
echo "  dmg       $DMG"
echo "  download  ${DMG_MB} MB"
echo "  sha256    $HASH"
