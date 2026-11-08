#!/bin/bash
# Vorschaubilder aller Ansichten in Hell und Dunkel – mit der Test-Kopie OHNE Sandbox (build/QA/…),
# eigenem Datenordner und einer Kopie der Testvideos. Die Bibliothek entsteht durch echtes Durchsuchen.
#
#   scripts/run_snapshots.sh build/QA/Filmbibliothek.app snapshots/glass
#   FB_FORCE_GLASS_FALLBACK=1 scripts/run_snapshots.sh build/QA/Filmbibliothek.app snapshots/fallback
#   SNAPSHOT_ARCH=x86_64 …   → Intel-Teil (auf Apple Silicon über Rosetta)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$1"
mkdir -p "$2"
OUT="$(cd "$2" && pwd)"
BIN="$APP/Contents/MacOS/Filmbibliothek"
test -x "$BIN" || { echo "Programmdatei fehlt: $BIN"; exit 1; }
WORK="$(mktemp -d)"
cp -R "$ROOT/Tests/Fixtures/Videos" "$WORK/Filme"
EXTRA=()
if [ -n "${SNAPSHOT_MANY:-}" ]; then
    # Echte (leere) Dateien in vielen Ordnern für den Messlauf
    python3 - "$WORK/Viele Testdateien" "$SNAPSHOT_MANY" <<'PY'
import os, sys
root, n = sys.argv[1], int(sys.argv[2])
for i in range(n):
    d = os.path.join(root, f"Ordner {i // 50:03d}")
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, f"Video {i}.mkv"), "wb").close()
PY
    EXTRA=(--library2 "$WORK/Viele Testdateien")
fi
RUNNER=()
[ -n "${SNAPSHOT_ARCH:-}" ] && RUNNER=(arch "-$SNAPSHOT_ARCH")
echo "▸ Vorschaubilder → $OUT ($(uname -m), App-Architektur ${SNAPSHOT_ARCH:-nativ})"
set +e
FB_DATA_DIR="$WORK/daten" FB_QA=1 perl -e 'alarm shift; exec @ARGV' "${SNAPSHOT_TIMEOUT:-1200}" ${RUNNER[@]+"${RUNNER[@]}"} "$BIN" \
    --snapshot "$OUT" --library "$WORK/Filme" ${EXTRA[@]+"${EXTRA[@]}"} > "$OUT/protokoll.txt" 2>&1
STATUS=$?
set -e
tail -n 60 "$OUT/protokoll.txt"
if [ $STATUS -ne 0 ]; then
    echo "✗ App beendet mit Status $STATUS"
    sleep 6
    cp "$HOME"/Library/Logs/DiagnosticReports/Filmbibliothek* "$OUT/" 2>/dev/null || true
    exit $STATUS
fi
test -f "$OUT/manifest.json" || { echo "✗ manifest.json fehlt"; exit 1; }
python3 - "$OUT/manifest.json" <<'PY'
import json, sys, os
m = json.load(open(sys.argv[1]))
imgs = m["images"]
print(f"  macOS {m['macOS']} · {m['architecture']} · Rosetta {m['rosetta']} · {m['glass']} · VLCKit {m['vlckit']} · {m['films']} Filme")
bad = [e for e in imgs if e.get("method") == "failed" or not os.path.exists(os.path.join(os.path.dirname(sys.argv[1]), e.get("file", "")))]
for e in bad: print("  ✗", e)
print(f"  {len(imgs)} Bilder, fehlerhaft: {len(bad)}")
sys.exit(1 if bad or not imgs else 0)
PY
echo "✓ Vorschaubilder vollständig"
