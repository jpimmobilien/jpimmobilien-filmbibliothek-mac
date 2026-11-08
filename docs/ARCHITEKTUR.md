# Technische Dokumentation

## Module (Swift-Paket, `Package.swift`)

| Modul | Inhalt | Abhängigkeiten |
|---|---|---|
| `FBCore` | Modelle (Film, Speicherort, Laufwerkskennung), Formate, Titel-Bereinigung, Suche, Filter, Sortierung, Bereiche der Seitenleiste, Fortsetzen-Regeln, Warteschlange, Abgleich Index ↔ Laufwerk (`ScanDiff`), Poster-/Untertitel-Erkennung, SRT/WebVTT-Leser, deutsche Formatierung | nur Foundation |
| `FBStore` | SQLite-Datenbank: Schema mit Versionsnummer, Speicherorte, Filme, Favoriten, Fortschritt, Verlauf, Sammlungen; threadsicher (Sperre), Scan-Ergebnisse in einer Transaktion | FBCore, System-SQLite |
| `FBServices` | Laufwerke (`VolumeInspector`, `VolumeMonitor`), Sandbox-Lesezeichen (`SecurityScope`, `ScopedAccess`), Speicherorte prüfen (`LocationResolver`), Scanner, Metadaten (`AVProbe`, `VLCSupport`), Titelbilder (`CoverStore`), Wiedergabe (`AVPlaybackEngine`, `VLCPlaybackEngine`) | FBCore, FBStore, AppKit, AVFoundation, VLCKit |
| `Filmbibliothek` | App: Zustand (`AppModel`, `AppSettings`), Oberfläche (SwiftUI + AppKit), Gestaltung (Liquid Glass), Player-Fenster, Menüs, QA-Abläufe | alle oben, AVKit, IOKit |

Zuständigkeiten laut Auftrag: Oberfläche → `Filmbibliothek/Views`, `Design`; Bibliotheksverwaltung → `AppModel`;
Dateizugriff/Berechtigungen → `FBServices/Volumes.swift`, `Locations.swift`; Speicherortverwaltung → `AppModel` +
`LocationResolver`; Scanner → `LibraryScanner`; Metadaten → `MetadataService`, `AVProbe`, `VLCSupport`, `CoverStore`;
Datenbank → `FBStore`; Player → `PlaybackEngine.swift`, `VLCPlaybackEngine.swift`, `Player/`; Einstellungen →
`AppSettings`, `SettingsView`.

## Nebenläufigkeit

- `AppModel`, Oberfläche und Player laufen auf dem Haupt-Thread (`@MainActor`).
- Durchsuchen: eigener Hintergrund-Task (`Task.detached`, Priorität `.utility`), abbrechbar; Fortschritt wird gedrosselt (≈ 8×/s) an die Oberfläche gemeldet.
- Prüfen der Speicherorte: je Ort ein Hintergrund-Task – ein hängendes Netzlaufwerk blockiert weder die Oberfläche noch andere Orte.
- Metadaten/Titelbilder: Hintergrund-Schleife mit höchstens zwei gleichzeitigen Dateien (schont langsame Laufwerke).
- Suche/Filter/Sortierung: im Hintergrund berechnet, Eingaben entprellt (120 ms); frühere Berechnungen werden abgebrochen.
- Datenbank: eine Verbindung, Zugriffe über eine Sperre serialisiert; WAL-Modus.

## Speicherorte und Berechtigungen

1. Der Nutzer wählt einen Ordner bzw. ein Laufwerk (NSOpenPanel, Ziehen ins Fenster, Ziehen aufs Dock-Symbol,
   „Öffnen mit“). macOS gewährt der App dafür einen vorübergehenden Sandbox-Zugriff.
2. Die App speichert ein sicherheitsgeschütztes Lesezeichen (`.withSecurityScope`, `.securityScopeAllowOnlyReadAccess`)
   und die Laufwerkskennung (`VolumeIdentity`):
   - Volume-UUID (`URLResourceKey.volumeUUIDStringKey`) – APFS, HFS+, exFAT, FAT,
   - Netzlaufwerk: Freigabe-Adresse (`volumeURLForRemountingKey`, ohne Benutzername/Passwort),
   - sonst Fingerabdruck aus Dateisystem, Größe und Erstellungsdatum – nie nur der Name.
3. Filme werden relativ zum Speicherort gespeichert; der absolute Pfad ist nur ein Hinweis.
4. Beim Start und bei jedem Laufwerksereignis (`NSWorkspace.didMount/willUnmount/didUnmount/didRenameVolume/didWake`,
   dazu alle 45 s für Netzlaufwerke) wird jedes Lesezeichen ohne Einbinden und ohne Dialog aufgelöst
   (`.withoutMounting`, `.withoutUI`). Ergebnis: verfügbar / nicht angeschlossen / kein Zugriff / Ordner fehlt.
5. `willUnmount`: laufendes Durchsuchen wird abgebrochen, ein Film von diesem Laufwerk wird angehalten und
   freigegeben (Position gesichert) – macOS kann das Laufwerk auswerfen.

Berechtigungen (`Resources/Filmbibliothek.entitlements`): `app-sandbox`, `files.user-selected.read-only`,
`files.bookmarks.app-scope`. Keine Netzwerk-, Kamera-, Mikrofon- oder Schreibrechte, kein Festplattenvollzugriff.

## Scanner und Index

- `FileManager.enumerator` mit vorab angeforderten Ressourcenwerten (Größe, Änderungsdatum, Typ, Paket), ohne
  Paketinhalte; übersprungen: versteckte Dateien, AppleDouble-Dateien („._“), Papierkörbe, Systemordner,
  NAS-Hilfsordner, Teil-Downloads, Unterordner, die zu einem anderen Speicherort gehören (keine Duplikate).
- Abgleich (`ScanDiff`): neu / geändert (Größe oder Datum, FAT-Toleranz 2 s) / umbenannt-verschoben (Inode bzw.
  Name+Größe+Datum) / fehlend / wieder da. Nicht lesbare Ordner schützen ihre Einträge.
- Nur ein **vollständiger** Durchlauf darf Dateien als fehlend markieren. Abbruch oder verschwundenes Laufwerk →
  nichts wird geändert.
- Nichts wird automatisch gelöscht. „Fehlende Einträge entfernen“ und „Speicherort entfernen“ sind bewusste
  Aktionen mit Bestätigung.
- Metadaten werden nur für neue/geänderte Dateien ermittelt (`metadataVersion`).

## Metadaten und Titelbilder

- Apple-Container (MP4, M4V, MOV, 3GP): AVFoundation (`AVURLAsset.load`), Abspielbarkeit aller Videospuren wird geprüft.
- Übrige Formate bzw. wenn AVFoundation scheitert: libVLC (`VLCMedia.parse`, nur lokal, mit Zeitlimit).
- Titelbild: Posterdatei im Ordner → eingebettetes Cover → Bild aus dem Video (dunkle Bilder werden übersprungen).
  Gespeichert als verkleinerte JPEG-Kopie im Cache der App, nie neben den Filmen.
- Fehlt die Datei während der Prüfung (Laufwerk gezogen), wird nichts gespeichert und später erneut versucht.

## Wiedergabe

| Engine | Formate | Umsetzung |
|---|---|---|
| AVFoundation | MP4, M4V, MOV (H.264, HEVC, ProRes …) | `AVPlayer` + `AVPlayerLayer`, Spuren über `AVMediaSelectionGroup`, Kapitel aus den Metadaten, externe SRT/WebVTT über eigene Untertitel-Ebene |
| VLCKit 3.7.3 | MKV, AVI, WMV, MPG, MPEG, TS, MTS, M2TS, WEBM, FLV (und MP4 mit nicht unterstützten Codecs) | `VLCMediaPlayer` + `VLCVideoView`, Spuren/Untertitel/Kapitel von libVLC, externe Untertitel (auch ASS/SSA) |

- Engine-Wahl nach Prüfergebnis; scheitert AVFoundation beim Abspielen, folgt automatisch ein Versuch mit VLCKit.
- Position: beim Pausieren, Schließen, Wechsel, Beenden und alle 10 s; Ruhezustand des Bildschirms wird während
  der Wiedergabe verhindert (IOKit-Assertion).
- Datei verschwindet (Laufwerk gezogen): die Engine meldet einen Fehler, der Player zeigt eine Meldung statt abzustürzen.

### Entscheidung VLCKit statt mpv

| | VLCKit 3.7.3 | libmpv |
|---|---|---|
| Lizenz | LGPL 2.1 (dynamisch eingebunden, zulässig) | standardmäßig GPL; LGPL nur mit Sonder-Build |
| Bezug | offizielle Universal-Binärdatei (arm64 + x86_64) von VideoLAN, Prüfsumme festgelegt | keine offizielle macOS-Bibliothek; FFmpeg + mpv selbst für zwei Architekturen bauen |
| Größe | + ca. 40–60 MB in der DMG (siehe Testbericht) | ähnlich |
| Wartung | aktiv gepflegt (3.7.x) | Eigenbau-Kette nötig |

## Gestaltung (Liquid Glass)

- `Design/Theme.swift`: Farbtokens für Dunkel und Hell, Schriften.
- `Design/Glass.swift`: macOS 26 + SDK 26 → `glassEffect(_:in:)`, `GlassEffectContainer`; sonst Nachbildung mit
  `NSVisualEffectView` (Unschärfe), Tönung, Glanz und Lichtkante. Keine privaten Schnittstellen.
- `Design/Components.swift`: Kapselknöpfe, Glas-Symbolknöpfe, Chips, Karten, Infozeilen, Hinweisleiste, Balken.

## Daten

- Bibliothek: `~/Library/Containers/de.privateapp.filmbibliothek/Data/Library/Application Support/Filmbibliothek/Bibliothek.sqlite`
- Titelbilder: `…/Data/Library/Caches/Filmbibliothek/Covers/<Film-ID>.jpg`
- Einstellungen: UserDefaults im Container.

## Tests

- `FBCoreTests` (Logik), `FBStoreTests` (Datenbank), `FBServicesTests` (macOS: echte Testvideos aller 13 Formate,
  echte Disk-Images APFS/exFAT/FAT32 mit Auswerfen und Wiedereinbinden an anderem Ort, Auswerfen während
  Durchsuchen und Wiedergabe, Wiedergabe mit beiden Engines).
- `scripts/qa_sandbox.sh`: die echte, sandboxte App auf einem Disk-Image (Öffnen-Ereignis → Lesezeichen →
  Auswerfen → anderer Einhängepunkt → Neustart → Wiedergabe), Ergebnisse aus dem macOS-Protokoll.
- `scripts/run_snapshots.sh`: Vorschaubilder aller Ansichten in Hell/Dunkel aus einer echt durchsuchten Testbibliothek.
