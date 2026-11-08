# Testbericht – Filmbibliothek für macOS 1.0.0

Stand: GitHub-Actions-Lauf 9 vom 08.11.2026 (Commit `80ed2ce`), alle drei Jobs grün.
Alle Prüfungen laufen automatisch auf **virtuellen Macs von GitHub**. Es wurde **nichts von Hand auf einem echten
Mac bedient** – siehe „Nicht geprüft“.

## Prüfumgebungen

| Umgebung | Prozessor | Was dort lief |
|---|---|---|
| macOS 26.7.2, Xcode 26 | Apple Silicon (VM) | Build, 69 Tests, Sandbox-Ablauf, Vorschaubilder mit echtem Liquid Glass und mit Nachbildung, Messlauf 5.022 Dateien, Xcode-Projekt-Build, DMG |
| macOS 15.8.2 | Apple Silicon (VM) | App aus der DMG installiert, Sandbox-Ablauf, Vorschaubilder (Nachbildung) |
| macOS 15.8.2 über Rosetta 2 | x86_64-Code auf Apple Silicon | derselbe Sandbox-Ablauf und Vorschaubilder mit dem Intel-Teil der App |
| macOS 15 | Intel x86_64 (VM) | 69 Tests nativ auf Intel (Scanner, Datenbank, Laufwerke, AVFoundation, VLCKit) |

## Ergebnisse

**Architekturen** (geprüft mit `lipo`): App-Programmdatei `x86_64 arm64`, VLCKit.framework `x86_64 arm64`.
Mindest-macOS im Programm: 13.0.

**Paket**: ad-hoc signiert (`codesign`: Signature=adhoc), Berechtigungen nur `app-sandbox`,
`files.user-selected.read-only`, `files.bookmarks.app-scope`. Gatekeeper (`spctl`) lehnt ab – erwartbar ohne
Developer ID. DMG: 37 MB, `hdiutil verify` gültig, enthält App, Verknüpfung „Applications“ und
„Installation – bitte lesen.txt“. SHA-256 siehe `.sha256`-Datei.

**Automatische Tests (69, alle bestanden auf Apple Silicon und auf Intel)**
- Kernlogik: Titelbereinigung, Formate, Pfade, Suche (UND, Ausschluss, Anführungszeichen, Unicode), Filter,
  Sortierung, Fortsetzen-Regeln, Warteschlange/Zufall, Abgleich beim Durchsuchen (neu, geändert, umbenannt,
  verschoben, fehlend, wieder da, unlesbarer Ordner), Laufwerkskennung, Poster/Untertitel, Signaturerkennung.
- Datenbank: Schema, Integrität, Speicherorte, Nutzerdaten bleiben bei Umbenennen/Verschieben, „fehlend“ statt
  löschen, Sammlungen, Verlauf, gleichzeitiger Zugriff, neueres Schema wird abgelehnt.
- Scanner mit echten Testvideos: genau die 22 erwarteten Videos, Hilfsdateien/Papierkörbe/Pakete übersprungen,
  Abbruch ändert nichts.
- **Echte Laufwerke (Disk-Images mit APFS, exFAT, FAT32)**: hinzufügen, auswerfen → „nicht verfügbar“, Einträge
  bleiben, an anderem Einhängepunkt wieder einbinden → wiedererkannt, keine Datei fehlt. Auswerfen während des
  Durchsuchens → nichts wird als fehlend markiert. Gelöschter Ordner auf vorhandenem Laufwerk → „Ordner nicht gefunden“.
  Hinweis Intel: FAT32 meldete nach dem Wiedereinbinden eine andere Volume-UUID; erkannt wurde der Ort über das
  Lesezeichen (die App zieht die Kennung nach).
- Metadaten: AVFoundation liest MP4/HEVC/M4V/MOV (Auflösung, Codec, fps, Dauer, Kapitel, eingebettetes Cover);
  VLCKit liest MKV, AVI, WMV, MPG, MPEG, TS, MTS, M2TS, WEBM, FLV (Dauer, Bildgröße, Spuren). Kaputte Dateien
  (Zufallsdaten, leere Datei, Text mit Video-Endung) → „nicht abspielbar“.
- Wiedergabe: AVFoundation (MP4 mit Kapiteln, Springen, Pause) und VLCKit (MKV mit 2 Ton- und 1 Untertitelspur;
  zusätzlich AVI, WMV, MPG, MPEG, TS, M2TS, WEBM, FLV, MTS – Zeit läuft je ≥ 0,5 s).
- Auswerfen während der Wiedergabe: VLCKit meldet „Die Datei ist nicht mehr erreichbar …“; AVFoundation spielt
  eine kleine, vollständig gepufferte Datei weiter (kein Absturz); erneutes Öffnen scheitert bei beiden sauber.

**Sandbox-Ablauf mit der echten App (macOS 26, macOS 15, Rosetta – jeweils bestanden)**
1. Start mit Ordner auf einem eingebundenen Laufwerk (wie „aufs Dock-Symbol ziehen“) → läuft in der Sandbox,
   22 Filme, Lesezeichen gespeichert (8 × AVFoundation, 11 × VLCKit, 3 × nicht abspielbar = die kaputten Testdateien).
2. Laufwerk auswerfen → erkannt, alle 22 Filme bleiben („nicht verfügbar“).
3. An anderem Einhängepunkt wieder einbinden → an der Volume-UUID wiedererkannt, keiner fehlt.
4. App beenden, ohne Ordner neu starten → Zugriff über das gespeicherte Lesezeichen; AVFoundation und VLCKit spielen,
   kaputte Datei → Meldung statt Absturz.

**Messlauf 5.022 Dateien** (macOS 26, Apple Silicon): Durchsuchen + Analyse 12,1 s, Suche 0,4 s, alle anzeigen
0,4 s, Sortieren 0,24 s. (Die 5.000 Zusatzdateien sind echte, aber leere Dateien – sie prüfen Durchsuchen und
Oberfläche, nicht die Dekodierung.)

**Vorschaubilder**: 28 (macOS 26, Liquid Glass) bzw. 26 je weitere Umgebung, hell und dunkel, alle Ansichten
inklusive Einstellungen und Player – alle erzeugt, keines fehlerhaft.

**Xcode-Projekt** (`xcodegen generate`): Release-Build erfolgreich, Universal (`x86_64 arm64`), Sandbox-Berechtigungen.

## Bekannte Befunde
- MPEG-Transportströme (.ts/.mts/.m2ts): abspielbar, Bildgröße und Codecs bekannt, aber kein automatisches Titelbild
  (VLCKit liefert dort kein Vorschaubild) → Titelbild nach dem ersten Abspielen.
- Intel-VM von GitHub: Die Oberfläche lässt sich dort nicht starten – Apples Metal-Bibliothek bricht auf der
  virtuellen Grafik („Apple Paravirtualized Graphics Device“) ab. Das betrifft die VM, nicht echte Intel-Macs mit
  Grafikchip. Der Intel-Code der App wurde deshalb unter Rosetta mit der vollständigen Oberfläche geprüft und auf der
  Intel-VM mit allen 69 Tests ohne Oberfläche.

## Nicht geprüft (keine echte Hardware verfügbar)
- Bedienung von Hand (Maus, Tastatur, Ziehen aus dem Finder, Menüs, Kontextmenüs, Vollbild-Gesten).
- Echte USB-Sticks, SD-Karten, externe SSD/HDD, NAS/SMB-Freigaben, langsame Laufwerke; Abziehen eines Steckers.
- macOS 13 Ventura und macOS 14 Sonoma (GitHub bietet diese Systeme nicht mehr an), echte Intel-Macs.
- Externe Bildschirme, Ruhezustand/Aufwachen, Wechsel Hell/Dunkel während des Betriebs.
- Große echte Filmsammlungen (Tausende echte Videos), sehr große Einzeldateien, HDR, Ton über AirPlay.
- Update auf eine spätere Version mit ad-hoc-Signatur (Zuordnung der gespeicherten Ordnerfreigaben).
