#!/bin/bash
# Beglaubigung („Notarisierung“) der DMG durch Apple – nur mit eigenem Apple-Developer-Konto.
#
# Ohne Zugangsdaten macht das Skript nichts (Ausgabe „übersprungen“) und der Build bleibt ad-hoc signiert.
# Mit Zugangsdaten (als GitHub-Secrets oder Umgebungsvariablen):
#
#   MACOS_CERT_P12_BASE64   Developer-ID-Application-Zertifikat samt privatem Schlüssel (.p12, Base64)
#   MACOS_CERT_PASSWORD     Passwort der .p12-Datei
#   NOTARY_APPLE_ID         Apple-ID des Developer-Kontos
#   NOTARY_TEAM_ID          Team-ID (10 Zeichen, developer.apple.com → Membership)
#   NOTARY_PASSWORD         app-spezifisches Passwort (appleid.apple.com → Anmeldung & Sicherheit)
#
#   scripts/notarize.sh keychain     → Zertifikat in einen temporären Schlüsselbund laden und
#                                       SIGN_IDENTITY für scripts/build_app.sh setzen (GitHub Actions)
#   scripts/notarize.sh dmg          → dist/Filmbibliothek_macOS_Universal.dmg signieren, einreichen, Ticket anheften
set -euo pipefail
cd "$(dirname "$0")/.."

have_credentials() {
    [ -n "${MACOS_CERT_P12_BASE64:-}" ] && [ -n "${MACOS_CERT_PASSWORD:-}" ] &&
    [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ]
}

if ! have_credentials; then
    echo "Beglaubigung übersprungen: keine Developer-ID-Zugangsdaten hinterlegt (Build bleibt ad-hoc signiert)."
    exit 0
fi

KEYCHAIN="${RUNNER_TEMP:-$(mktemp -d)}/filmbibliothek-signing.keychain-db"

case "${1:-}" in
keychain)
    PASS="$(uuidgen)"
    P12="$(mktemp)"
    echo "$MACOS_CERT_P12_BASE64" | base64 --decode > "$P12"
    security create-keychain -p "$PASS" "$KEYCHAIN"
    security set-keychain-settings -lut 21600 "$KEYCHAIN"
    security unlock-keychain -p "$PASS" "$KEYCHAIN"
    security import "$P12" -P "$MACOS_CERT_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
    security set-key-partition-list -S apple-tool:,apple: -k "$PASS" "$KEYCHAIN" >/dev/null
    security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
    rm -f "$P12"
    IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)"/\1/')"
    test -n "$IDENTITY" || { echo "Kein „Developer ID Application“-Zertifikat in der .p12-Datei"; exit 1; }
    echo "Signatur-Identität: $IDENTITY"
    # Für die folgenden Schritte in GitHub Actions bereitstellen
    if [ -n "${GITHUB_ENV:-}" ]; then echo "SIGN_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"; fi
    ;;
dmg)
    DMG="dist/Filmbibliothek_macOS_Universal.dmg"
    test -f "$DMG"
    IDENTITY="${SIGN_IDENTITY:?SIGN_IDENTITY fehlt}"
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
    xcrun notarytool submit "$DMG" --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" \
        --password "$NOTARY_PASSWORD" --wait --timeout 30m
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
    (cd dist && shasum -a 256 "Filmbibliothek_macOS_Universal.dmg" | tee "Filmbibliothek_macOS_Universal.dmg.sha256")
    echo "✓ beglaubigt: $DMG"
    ;;
*)
    echo "Aufruf: scripts/notarize.sh keychain|dmg"; exit 2 ;;
esac
