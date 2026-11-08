#!/bin/bash
# Baut „Filmbibliothek.app“ als Universal Binary (arm64 + x86_64) mit eingebettetem VLCKit.
#
#   scripts/build_app.sh                               → build/Filmbibliothek.app (App-Sandbox, ad-hoc signiert)
#                                                         build/QA/Filmbibliothek.app (gleiche Programmdatei, ohne Sandbox – nur für Tests)
#   VERSION=1.0.0 BUILD_NUMBER=42 scripts/build_app.sh
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build_app.sh   → Developer-ID-Signatur mit Hardened Runtime
#
# Voraussetzung: macOS mit Xcode 16 oder neuer (für echtes Liquid Glass: Xcode 26 mit macOS-26-SDK).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP="build/Filmbibliothek.app"
QA_APP="build/QA/Filmbibliothek.app"
ENT="Resources/Filmbibliothek.entitlements"

echo "▸ Swift: $(swift --version 2>&1 | head -1)"
echo "▸ SDK: macOS $(xcrun --show-sdk-version 2>/dev/null || echo '?')"
scripts/fetch_vlckit.sh || echo "⚠︎ VLCKit nicht verfügbar – Build nur mit AVFoundation"

SLICES=()
for ARCH in arm64 x86_64; do
    TRIPLE="$ARCH-apple-macosx13.0"
    echo "▸ Baue $ARCH ($TRIPLE) …"
    swift build -c release --triple "$TRIPLE" --product Filmbibliothek
    BIN_DIR="$(swift build -c release --triple "$TRIPLE" --show-bin-path)"
    test -f "$BIN_DIR/Filmbibliothek" || { echo "✗ Programmdatei fehlt: $BIN_DIR/Filmbibliothek"; exit 1; }
    SLICES+=("$BIN_DIR/Filmbibliothek")
done
mkdir -p build
lipo -create "${SLICES[@]}" -output build/Filmbibliothek-universal

echo "▸ App-Paket …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Licenses" "$APP/Contents/Frameworks"
cp build/Filmbibliothek-universal "$APP/Contents/MacOS/Filmbibliothek"
sed -e "s/\$(MARKETING_VERSION)/$VERSION/" -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Licenses/* "$APP/Contents/Resources/Licenses/" 2>/dev/null || true
[ -f Resources/Anleitung.html ] && cp Resources/Anleitung.html "$APP/Contents/Resources/"

if [ -d Vendor/VLCKit.xcframework ]; then
    FW="$(find Vendor/VLCKit.xcframework -maxdepth 2 -type d -name VLCKit.framework -path '*macos*' | head -1)"
    test -n "$FW" || { echo "✗ macOS-Teil von VLCKit fehlt"; exit 1; }
    ditto "$FW" "$APP/Contents/Frameworks/VLCKit.framework"
    [ -f Vendor/VLCKit-COPYING.txt ] && cp Vendor/VLCKit-COPYING.txt "$APP/Contents/Resources/Licenses/VLCKit-LGPL-2.1.txt"
    # Programmdatei findet das Framework unter Contents/Frameworks
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Filmbibliothek"
else
    rmdir "$APP/Contents/Frameworks"
fi
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "▸ Architekturen:"
lipo -info "$APP/Contents/MacOS/Filmbibliothek"
lipo "$APP/Contents/MacOS/Filmbibliothek" -verify_arch arm64 x86_64
if [ -d "$APP/Contents/Frameworks/VLCKit.framework" ]; then
    VB="$APP/Contents/Frameworks/VLCKit.framework/VLCKit"
    echo "  VLCKit: $(lipo -archs "$VB")"
    lipo "$VB" -verify_arch arm64 x86_64
fi
echo "▸ Mindest-macOS je Architektur:"
for A in arm64 x86_64; do
    echo "  $A: $(otool -l -arch $A "$APP/Contents/MacOS/Filmbibliothek" | grep -A4 LC_BUILD_VERSION | grep -E 'minos|sdk' | tr -s ' ' | tr '\n' ' ')"
done
echo "▸ Verknüpfte Bibliotheken (arm64):"
otool -L -arch arm64 "$APP/Contents/MacOS/Filmbibliothek" | sed 's/^/  /'

xattr -cr "$APP"
sign() { # $1 = Ziel, $2 = Entitlements (optional)
    local args=(--force --sign "${SIGN_IDENTITY:--}")
    if [ -n "${SIGN_IDENTITY:-}" ]; then args+=(--options runtime --timestamp); else args+=(--timestamp=none); fi
    if [ -n "${2:-}" ]; then args+=(--entitlements "$2"); fi
    codesign "${args[@]}" "$1"
}
echo "▸ Signatur (${SIGN_IDENTITY:-ad-hoc}) …"
if [ -d "$APP/Contents/Frameworks/VLCKit.framework" ]; then sign "$APP/Contents/Frameworks/VLCKit.framework"; fi
sign "$APP" "$ENT"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "▸ Berechtigungen (Entitlements):"
codesign -d --entitlements - "$APP" 2>/dev/null | sed 's/^/  /' || true

echo "▸ Test-Kopie ohne Sandbox (nur für automatische Tests, nicht für die DMG) …"
rm -rf build/QA
mkdir -p build/QA
ditto "$APP" "$QA_APP"
if [ -d "$QA_APP/Contents/Frameworks/VLCKit.framework" ]; then codesign --force --sign - --timestamp=none "$QA_APP/Contents/Frameworks/VLCKit.framework"; fi
codesign --force --sign - --timestamp=none "$QA_APP"
codesign --verify --deep --strict "$QA_APP"
echo "✓ $APP"
