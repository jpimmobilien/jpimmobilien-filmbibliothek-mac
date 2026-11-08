#!/bin/bash
# Lädt VLCKit 3.7.3 (offizielle Binärdatei von VideoLAN, LGPL 2.1) nach Vendor/VLCKit.xcframework.
# Quelle und Prüfsumme stammen aus der offiziellen CocoaPods-Beschreibung (Specs/5/f/4/VLCKit/3.7.3).
# Ohne VLCKit baut das Paket trotzdem – dann spielt die App nur, was AVFoundation kann.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="3.7.3"
URL="https://download.videolan.org/pub/cocoapods/prod/VLCKit-3.7.3-319ed2c0-79128878.tar.xz"
SHA256="019afdae4e2e2d0f3ac325fac8f7ba0af25dca70b9d157df7d60db88e0be8e5d"
MARKER="Vendor/.vlckit-$VERSION"

if [ -d Vendor/VLCKit.xcframework ] && [ -f "$MARKER" ]; then
    echo "▸ VLCKit $VERSION ist bereits vorhanden"
    exit 0
fi

WORK="build/vlckit-download"
rm -rf "$WORK"
mkdir -p "$WORK" Vendor
echo "▸ Lade VLCKit $VERSION …"
curl -L --fail --retry 4 --retry-delay 5 -o "$WORK/vlckit.tar.xz" "$URL"
echo "$SHA256  $WORK/vlckit.tar.xz" | shasum -a 256 -c -
tar -xJf "$WORK/vlckit.tar.xz" -C "$WORK"
XC="$(find "$WORK" -maxdepth 4 -type d -name 'VLCKit.xcframework' | head -1)"
test -n "$XC" || { echo "✗ VLCKit.xcframework nicht im Archiv"; find "$WORK" -maxdepth 3; exit 1; }
rm -rf Vendor/VLCKit.xcframework
ditto "$XC" Vendor/VLCKit.xcframework
# Lizenztext (LGPL 2.1) mitnehmen
LIC="$(find "$WORK" -maxdepth 4 -type f \( -name 'COPYING*' -o -name 'LICENSE*' \) | head -1)"
if [ -n "$LIC" ]; then cp "$LIC" Vendor/VLCKit-COPYING.txt; fi
echo "▸ Inhalt:"
find Vendor/VLCKit.xcframework -maxdepth 2 | sed 's/^/  /'
# Modul-Beschreibung für Swift (falls das Framework keine mitbringt)
for FW in $(find Vendor/VLCKit.xcframework -type d -name 'VLCKit.framework'); do
    if ! find "$FW" -name module.modulemap | grep -q .; then
        echo "▸ Ergänze module.modulemap in $FW"
        if [ -d "$FW/Versions/A" ]; then
            mkdir -p "$FW/Versions/A/Modules"
            printf 'framework module VLCKit {\n  umbrella header "VLCKit.h"\n  export *\n  module * { export * }\n}\n' > "$FW/Versions/A/Modules/module.modulemap"
            ln -sfn Versions/Current/Modules "$FW/Modules"
        else
            mkdir -p "$FW/Modules"
            printf 'framework module VLCKit {\n  umbrella header "VLCKit.h"\n  export *\n  module * { export * }\n}\n' > "$FW/Modules/module.modulemap"
        fi
    fi
    BIN="$FW/VLCKit"
    [ -e "$BIN" ] || BIN="$FW/Versions/A/VLCKit"
    echo "▸ $(basename "$(dirname "$FW")"): $(lipo -archs "$BIN" 2>/dev/null || echo '?')"
done
touch "$MARKER"
echo "✓ VLCKit $VERSION in Vendor/"
