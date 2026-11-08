# Filmbibliothek für macOS

Native macOS-Fassung der privaten Android-App *Filmbibliothek* – eine lokale Filmbibliothek für Filme auf
interner SSD, externen Laufwerken, USB-Sticks, SD-Karten und Netzlaufwerken. SwiftUI + AppKit, durchgehend im
Liquid-Glass-Stil (echtes Liquid Glass ab macOS 26, davor gleichwertige Nachbildung), Universal Binary für
Apple Silicon und Intel.

| | |
|---|---|
| macOS | 13 Ventura oder neuer |
| Prozessoren | Apple Silicon (arm64) und Intel (x86_64) in einer App |
| Wiedergabe | AVFoundation (MP4, M4V, MOV) · VLCKit 3.7.3 (MKV, AVI, WMV, MPG, MPEG, TS, MTS, M2TS, WEBM, FLV) |
| Datenschutz | App-Sandbox, nur Lesezugriff auf gewählte Ordner, kein Netzwerk, keine Konten, keine Telemetrie |

Dokumentation: [docs/](docs/) – Installation, Funktionen, Architektur, Testbericht, bekannte Grenzen.

## Bauen

```
scripts/fetch_vlckit.sh     # VLCKit 3.7.3 (offizielle Binärdatei, Prüfsumme festgelegt) nach Vendor/
swift test                  # alle Tests (macOS: echte Disk-Images und Wiedergabe)
scripts/build_app.sh        # build/Filmbibliothek.app (arm64 + x86_64, App-Sandbox, ad-hoc signiert)
scripts/make_dmg.sh         # dist/Filmbibliothek_macOS_Universal.dmg
```

In Xcode: `Package.swift` öffnen (Schema „Filmbibliothek“). GitHub Actions (`.github/workflows/build.yml`)
baut, testet und erstellt die DMG bei jedem Push; Ergebnisse liegen im Zweig `ci-ergebnisse`.
