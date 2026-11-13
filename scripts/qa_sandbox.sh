#!/bin/bash
# Prüft die ECHTE App (mit App-Sandbox, wie in der DMG) auf einem echten, eingebundenen Disk-Image:
#   1. Start mit Ordner (Öffnen-Ereignis wie „auf das Dock-Symbol ziehen“) → Lesezeichen, Durchsuchen, Analyse
#   2. Laufwerk auswerfen → Filme bleiben, Status „Nicht verfügbar“
#   3. Wieder einbinden an ANDEREM Einhängepunkt → an der Kennung erkannt
#   4. Beenden, Neustart OHNE Ordner → Zugriff über das gespeicherte Lesezeichen, Wiedergabe je Engine
#
#   scripts/qa_sandbox.sh build/Filmbibliothek.app qa/sandbox          (QA_ARCH=x86_64 → Intel-Teil über Rosetta)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
mkdir -p "$2"
OUT="$(cd "$2" && pwd)"
LOG="$OUT/app-protokoll.txt"
STATUS=0
fail() { echo "✗ $1"; STATUS=1; }
ok() { echo "✓ $1"; }

mark() { wc -l < "$LOG" | tr -d ' '; }
# Wartet, bis ein Muster in den Protokollzeilen NACH der Marke erscheint (Muster als grep-Ausdruck)
wait_new() { # Marke, Muster, Zeitlimit
    local since="$1" pattern="$2" t="$3" i=0
    while [ $i -lt "$t" ]; do
        tail -n +"$((since + 1))" "$LOG" | grep -q -- "$pattern" && return 0
        sleep 1; i=$((i + 1))
    done
    return 1
}
new_lines() { tail -n +"$(($1 + 1))" "$LOG"; }

pkill -x Filmbibliothek 2>/dev/null || true
log stream --style compact --level info --predicate 'subsystem == "de.privateapp.filmbibliothek"' > "$LOG" 2>&1 &
LOGPID=$!
trap 'kill $LOGPID 2>/dev/null; pkill -x Filmbibliothek 2>/dev/null; [ -n "${MNT2:-}" ] && hdiutil detach "$MNT2" -force >/dev/null 2>&1; [ -n "${MNT:-}" ] && hdiutil detach "$MNT" -force >/dev/null 2>&1' EXIT
sleep 2

TMP="$(mktemp -d)"
IMG="$TMP/qa.dmg"
hdiutil create -size 150m -fs APFS -volname "FB QA Filme" -ov "$IMG" >/dev/null
MNT="$(hdiutil attach "$IMG" | tail -1 | awk -F'\t' '{print $NF}')"
echo "▸ Testlaufwerk: $MNT"
mkdir -p "$MNT/Filme"
cp -R "$ROOT/Tests/Fixtures/Videos/." "$MNT/Filme/"
EXPECTED=22

OPEN=(open -n)
[ -n "${QA_ARCH:-}" ] && OPEN+=(--arch "$QA_ARCH")
echo "▸ Entitlements der App:"
codesign -d --entitlements - "$APP" 2>/dev/null | sed 's/^/  /'

echo "▸ 1. Start mit Ordner (Öffnen-Ereignis)"
M=$(mark)
"${OPEN[@]}" -a "$APP" "$MNT/Filme" --args --qa-scenario report
if wait_new "$M" "QA-RESULT scenario=report done" 360; then ok "Bericht 1"; else fail "Bericht 1 kam nicht"; fi
grep -q "QA-RESULT sandbox=true" "$LOG" && ok "App läuft in der Sandbox" || fail "App läuft NICHT in der Sandbox"
grep -q "status=Verfügbar films=$EXPECTED " "$LOG" && ok "$EXPECTED Filme gefunden, Speicherort verfügbar" || fail "erwartete $EXPECTED Filme / verfügbar"
grep -q "bookmark=true" "$LOG" && ok "Lesezeichen gespeichert" || fail "kein Lesezeichen"
grep "QA-RESULT films total" "$LOG" | tail -1

echo "▸ 2. Laufwerk auswerfen"
M=$(mark)
hdiutil detach "$MNT" >/dev/null 2>&1 || hdiutil detach "$MNT" -force >/dev/null
MNT=""
if wait_new "$M" "Laufwerk ausgeworfen" 30; then ok "Auswerfen erkannt"; else fail "Auswerfen nicht erkannt"; fi
sleep 2
M=$(mark)
notifyutil -p de.privateapp.filmbibliothek.qa.report
if wait_new "$M" "QA-RESULT report-done" 120; then ok "Bericht 2"; else fail "Bericht 2 kam nicht"; fi
new_lines "$M" | grep -q "status=Nicht verfügbar films=$EXPECTED " && ok "Filme bleiben erhalten (nicht verfügbar)" || fail "Filme nach Auswerfen nicht erhalten"

echo "▸ 3. Wieder einbinden an anderem Einhängepunkt"
MNT2="$TMP/anderer-ort"
mkdir -p "$MNT2"
M=$(mark)
hdiutil attach "$IMG" -mountpoint "$MNT2" >/dev/null
if wait_new "$M" "Speicherort verfügbar: Filme.*anderer-ort/Filme" 60; then ok "an der Kennung wiedererkannt (anderer Einhängepunkt)"; else fail "nicht wiedererkannt"; fi
new_lines "$M" | grep "Speicherort verfügbar" | tail -1
sleep 3
M=$(mark)
notifyutil -p de.privateapp.filmbibliothek.qa.report
if wait_new "$M" "QA-RESULT report-done" 120; then ok "Bericht 3"; else fail "Bericht 3 kam nicht"; fi
new_lines "$M" | grep -q "status=Verfügbar films=$EXPECTED missing=0" && ok "alle Filme wieder verfügbar, keiner fehlt" || fail "nach Wiedereinbinden nicht vollständig"

echo "▸ 4. Beenden und Neustart ohne Ordner (Lesezeichen)"
M=$(mark)
notifyutil -p de.privateapp.filmbibliothek.qa.quit
wait_new "$M" "Beendet" 30 && ok "App sauber beendet" || fail "App hat sich nicht beendet"
sleep 2
pkill -x Filmbibliothek 2>/dev/null || true
M=$(mark)
"${OPEN[@]}" -a "$APP" --args --qa-scenario playback --qa-quit
if wait_new "$M" "QA-RESULT scenario=playback done" 360; then ok "Wiedergabe-Ablauf"; else fail "Wiedergabe-Ablauf kam nicht"; fi
new_lines "$M" | grep -q "Speicherort verfügbar: Filme" && ok "Zugriff nach Neustart über das gespeicherte Lesezeichen" || fail "kein Zugriff nach Neustart"
new_lines "$M" | grep "QA-RESULT playback" | sed 's/.*QA-RESULT /  /'
new_lines "$M" | grep "QA-RESULT playback" | grep "engine=AVFoundation" | grep -Eq "advanced=([1-9]|0\.[5-9])" && ok "AVFoundation spielt (Zeit läuft)" || fail "AVFoundation-Wiedergabe"
if grep -q "vlckit=true" "$LOG"; then
    new_lines "$M" | grep "QA-RESULT playback" | grep "engine=VLCKit" | grep -Eq "advanced=([1-9]|0\.[5-9])" && ok "VLCKit spielt (Zeit läuft)" || fail "VLCKit-Wiedergabe"
fi
new_lines "$M" | grep "QA-RESULT playback" | grep "engine=AVFoundation" | grep -q "controls=aus" && ok "Steuerung blendet sich ohne Maus/Tastatur aus (AVFoundation)" || fail "Steuerung bleibt sichtbar (AVFoundation)"
if grep -q "vlckit=true" "$LOG"; then
    new_lines "$M" | grep "QA-RESULT playback" | grep "engine=VLCKit" | grep -v "Kaputt/" | grep -q "controls=aus" && ok "Steuerung blendet sich ohne Maus/Tastatur aus (VLCKit)" || fail "Steuerung bleibt sichtbar (VLCKit)"
fi
new_lines "$M" | grep "QA-RESULT playback" | grep "Kaputt/" | grep -vq "error=-" && ok "Kaputte Datei: Meldung statt Absturz" || echo "  (keine kaputte Datei abgespielt)"
if ls "$HOME"/Library/Logs/DiagnosticReports/Filmbibliothek* >/dev/null 2>&1; then
    fail "Absturzbericht gefunden"
    cp "$HOME"/Library/Logs/DiagnosticReports/Filmbibliothek* "$OUT/" 2>/dev/null
fi
grep "QA-RESULT" "$LOG" | sed 's/.*QA-RESULT /QA-RESULT /' > "$OUT/ergebnisse.txt"
echo "▸ Ergebnis: $([ $STATUS -eq 0 ] && echo bestanden || echo FEHLER)"
exit $STATUS
