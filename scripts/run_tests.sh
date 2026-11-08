#!/bin/bash
# Führt die Swift-Tests aus.
#
# VLCKit trägt als Ladepfad „@loader_path/../Frameworks/VLCKit.framework“ (passend für Contents/MacOS in der App).
# Das Testbündel von `swift test` hat keinen Frameworks-Ordner – deshalb wird VLCKit nach dem Bauen der Tests
# in das Testbündel kopiert und erst dann getestet.
set -uo pipefail
cd "$(dirname "$0")/.."

swift build --build-tests || exit 1

FW="$(find Vendor/VLCKit.xcframework -maxdepth 2 -type d -name 'VLCKit.framework' -path '*macos*' 2>/dev/null | head -1)"
if [ -n "$FW" ]; then
    BIN_DIR="$(swift build --show-bin-path)"
    for XCT in "$BIN_DIR"/*.xctest; do
        [ -d "$XCT" ] || continue
        mkdir -p "$XCT/Contents/Frameworks"
        rm -rf "$XCT/Contents/Frameworks/VLCKit.framework"
        ditto "$FW" "$XCT/Contents/Frameworks/VLCKit.framework"
        echo "▸ VLCKit in $(basename "$XCT") kopiert"
    done
fi

swift test --skip-build
