# Testbericht – Filmbibliothek für macOS 1.1.0

Stand: GitHub-Actions-Lauf 19 vom 13.11.2026 (Commit `38bbd4e`).
Alle Prüfungen laufen automatisch auf **virtuellen Macs von GitHub**. Es wurde **nichts von Hand auf einem echten
Mac bedient** – siehe „Nicht geprüft“.

## Prüfumgebungen

| Umgebung | Prozessor | Was dort lief |
|---|---|---|
| macOS 26.7.2, Xcode 26.6 | Apple Silicon (VM) | Build, 69 Tests, Sandbox-Ablauf, 36 Vorschaubilder mit echtem Liquid Glass + 34 mit Nachbildung, Messlauf 5.022 Dateien, Xcode-Projekt-Build, DMG – **bestanden** |
| macOS 15, Xcode 26.3 | Intel x86_64 (VM) | App kompiliert, 69 Tests nativ in x86_64 |
| macOS 15 Apple Silicon und Rosetta | – | **In 1.1 nicht gelaufen:** GitHub hatte über Stunden keine Apple-Silicon-Rechner frei („capacity constraints“). In 1.0 bestanden. |

Hinweis: Auf den virtuellen Macs von GitHub ist „Bewegung reduzieren“ eingeschaltet. Die Vorschaubilder zeigen deshalb
die ruhige Variante (ohne Neigung und Lichtreflex) – genau die Darstellung, die auch Nutzer mit dieser Einstellung sehen.

## Ergebnisse

**Architekturen** (`lipo`): App `x86_64 arm64`, VLCKit.framework `x86_64 arm64`; Mindest-macOS 13.0, SDK macOS 26.5.

**Paket**: ad-hoc signiert (`Signature=adhoc`), Berechtigungen nur `app-sandbox`, `files.user-selected.read-only`,
`files.bookmarks.app-scope`. Gatekeeper (`spctl`) lehnt ab – erwartbar ohne Developer ID. DMG 38 MB,
`hdiutil verify` gültig. SHA-256 siehe `.sha256`-Datei.

**Automatische Tests (69)** – auf Apple Silicon (macOS 26) alle bestanden; auf Intel (x86_64 nativ) in den Läufen 14–18 alle bestanden, in Lauf 19 einer mit einem Aushäng-Fehler der Test-VM (siehe „Befunde“)
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

**Sandbox-Ablauf mit der echten App (macOS 26, Apple Silicon – bestanden)**
1. Start mit Ordner auf einem eingebundenen Laufwerk → läuft in der Sandbox, 22 Filme, Lesezeichen gespeichert
   (8 × AVFoundation, 11 × VLCKit, 3 × nicht abspielbar = die kaputten Testdateien).
2. Laufwerk auswerfen → erkannt, alle Filme bleiben („nicht verfügbar“).
3. An anderem Einhängepunkt wieder einbinden → an der Kennung wiedererkannt, keiner fehlt.
4. Beenden, Neustart ohne Ordner → Zugriff über das Lesezeichen; AVFoundation und VLCKit spielen, kaputte Datei → Meldung.

**Messlauf 5.022 Dateien** (macOS 26, Apple Silicon): Durchsuchen + Analyse 11,6 s, Suche 0,3 s, alle anzeigen 0,3 s,
Sortieren 0,14 s (die 5.000 Zusatzdateien sind leer – sie prüfen Durchsuchen und Oberfläche, nicht die Dekodierung).

**Vorschaubilder** (hell und dunkel, alle angesehen): Start mit Kinobild, Alle Filme groß/kompakt/Liste, Poster 2:3,
Weiterschauen, Suche mit Filtern, Speicherorte, Details, kleines Fenster (960 pt), **schmales Fenster (740 pt) für Start
und Filme**, Sammlungen, Einstellungen, Player (VLCKit und AVFoundation, pausiert), **Mini-Player** im Hauptfenster.
Geprüft wurde dabei u. a.: Navigation frei von den Fensterknöpfen, Werkzeugleiste vollständig sichtbar, keine
abgeschnittenen Inhalte.

**Xcode-Projekt** (`xcodegen generate`): Release-Build erfolgreich, Universal (`x86_64 arm64`).

## Befunde und Korrekturen in 1.1
- Lauf 18: Im schmalen Fenster (740 pt) war das Kinobild auf „Start“ breiter als das Fenster – Werkzeugleiste und
  „Alle anzeigen“ wurden rechts abgeschnitten. Korrigiert in Lauf 19: Das Plakat wird kleiner bzw. ausgeblendet, die
  Werkzeugleiste rückt bei Platzmangel unter den Titel.
- Lauf 19, Intel-VM: Ein Laufwerkstest scheiterte beim Aufräumen („hdiutil detach … No such file or directory“ – das
  Test-Laufwerk war schon ausgehängt). Die Prüfung selbst (Ordner gelöscht → „Ordner nicht gefunden“) war bestanden;
  die Testhilfe wertet ein bereits ausgehängtes Laufwerk jetzt nicht mehr als Fehler.
- MPEG-Transportströme (.ts/.mts/.m2ts): abspielbar, aber kein automatisches Titelbild (VLCKit liefert dort kein
  Vorschaubild) → Titelbild nach dem ersten Abspielen.
- Intel-VMs von GitHub: Die Oberfläche bricht dort in Apples Metal-Bibliothek ab („Apple Paravirtualized Graphics“) –
  eine Grenze der VM, nicht echter Intel-Macs. Auf Intel laufen deshalb Kompilieren und alle Tests ohne Oberfläche.

## Nicht geprüft (keine echte Hardware verfügbar)
- **Das Update-Szenario des Nutzers**: vorhandene Bibliothek mit Ordnerfreigaben aus 1.0 → 1.1 installieren →
  „Kein Zugriff“ und „Freigaben erneuern …“. Die neue Erkennung (interne SSD immer angeschlossen, Volume-UUID im
  Lesezeichen, Einhängepunkt) ist im Code umgesetzt und im Sandbox-Ablauf mit Disk-Images mitgelaufen, der echte
  Fall mit Freigaben einer älteren Version aber nicht.
- Bewegungen und Hover-Effekte (Neigung, Lichtreflex, Einblenden, Herz-Puls, Linse, Übergang zur Detailseite),
  Bedienung von Hand (Maus, Tastatur, Ziehen, Menüs, Vollbild).
- macOS 15 auf Apple Silicon und Intel-Code unter Rosetta für 1.1 (keine Rechner frei, siehe oben); macOS 13 und 14.
- Echte USB-Sticks, SD-Karten, externe SSD/HDD, NAS/SMB; Ruhezustand, externe Bildschirme; große echte Sammlungen.
