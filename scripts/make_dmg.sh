#!/bin/bash
# Erstellt dist/Filmbibliothek_macOS_Universal.dmg mit App, Verknüpfung „Applications“ und Installationsanleitung.
# Nutzt dmgbuild (Python, ohne Finder/AppleScript – zuverlässig auf CI-Maschinen).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Filmbibliothek.app"
NAME="Filmbibliothek_macOS_Universal"
OUT="dist/$NAME.dmg"
test -d "$APP" || { echo "Zuerst scripts/build_app.sh ausführen"; exit 1; }
mkdir -p dist build
rm -f "$OUT" "$OUT.sha256"

PY="build/dmg-venv/bin/python3"
if [ ! -x "$PY" ]; then
    python3 -m venv build/dmg-venv
    "$PY" -m pip install --quiet --upgrade pip
    "$PY" -m pip install --quiet "dmgbuild>=1.6,<2"
fi

BG="Resources/DMG/background.png"
if command -v tiffutil >/dev/null; then
    tiffutil -cathidpicheck Resources/DMG/background.png Resources/DMG/background@2x.png -out build/dmg-background.tiff
    BG="build/dmg-background.tiff"
fi
cp "docs/Installation – bitte lesen.txt" "build/Installation – bitte lesen.txt"

"$PY" -m dmgbuild -s scripts/dmg_settings.py -D app="$APP" -D background="$BG" \
    -D readme="build/Installation – bitte lesen.txt" "Filmbibliothek" "$OUT"

echo "▸ Prüfe DMG …"
hdiutil verify "$OUT"
MNT="$(mktemp -d)"
hdiutil attach "$OUT" -nobrowse -readonly -mountpoint "$MNT" >/dev/null
ls -la "$MNT"
test -d "$MNT/Filmbibliothek.app"
test -L "$MNT/Applications"
test -f "$MNT/Installation – bitte lesen.txt"
codesign --verify --deep --strict "$MNT/Filmbibliothek.app"
lipo "$MNT/Filmbibliothek.app/Contents/MacOS/Filmbibliothek" -verify_arch arm64 x86_64
hdiutil detach "$MNT" >/dev/null
(cd dist && shasum -a 256 "$NAME.dmg" | tee "$NAME.dmg.sha256")
echo "✓ $OUT ($(du -h "$OUT" | cut -f1))"
