# Funktionsliste – Filmbibliothek für macOS 1.0

Stand der Prüfung je Funktion: siehe [TESTBERICHT.md](TESTBERICHT.md).

## Bibliothek
- Speicherorte: Ordner oder ganze Laufwerke – interne SSD, externe SSD/HDD, USB-Sticks, SD-Karten, weitere Volumes, NAS/Netzlaufwerke (vorher im Finder verbunden).
- Hinzufügen über „Speicherort hinzufügen …“ (⌘O, Dialog mit Mehrfachauswahl), Ziehen aus dem Finder ins Fenster, Ziehen aufs Dock-Symbol, „Öffnen mit“.
- Dauerhafter Zugriff nach Neustart über sicherheitsgeschützte Lesezeichen (App-Sandbox, nur lesen).
- Klare Hinweise, wenn ein Ort nicht erreichbar ist: „Laufwerk nicht angeschlossen“, „Netzlaufwerk nicht verbunden“ (mit „Verbinden“), „Kein Zugriff“ (mit „Zugriff erteilen …“), „Ordner nicht gefunden“ (mit „Neu zuordnen …“).
- Entfernte Laufwerke: Filme bleiben mit Titelbild und Metadaten als „Nicht verfügbar“; Wiedererkennung an der Laufwerkskennung (UUID), auch bei anderem Namen oder Einhängepunkt.
- Nichts wird automatisch gelöscht; fehlende Dateien werden als „Datei fehlt“ markiert. „Fehlende Einträge entfernen“ und „Aus der Bibliothek entfernen“ nur mit Bestätigung – Videodateien werden nie verändert.
- Speicherort-Karten mit Status, Dateisystem, Belegungsbalken, Anzahl/Größe der Filme, letzter Durchlauf; umbenennbar.

## Durchsuchen
- Rekursiv, im Hintergrund, mit Fortschritt (Videos/Ordner/aktueller Ordner) und Abbrechen.
- Intelligenter Index: erneute Durchläufe lesen nur Verzeichniseinträge; Metadaten nur für neue/geänderte Dateien.
- Erkennt Umbenennen/Verschieben (Favorit, Fortschritt, Sammlungen bleiben), Änderungen, fehlende und wieder aufgetauchte Dateien.
- Überspringt versteckte Dateien, macOS-Begleitdateien, Papierkörbe, Systemordner, NAS-Hilfsordner, Pakete, Teil-Downloads, Überschneidungen mit anderen Speicherorten.
- Automatisch beim Start und beim Anschließen eines Laufwerks (abschaltbar); manuell ⌘R.

## Formate und Wiedergabe
- Erkannt: MP4, MKV, MOV, AVI, M4V, WMV, MPG, MPEG, TS, MTS, M2TS, WEBM, FLV (+ 3GP, OGV, VOB, DIVX, ASF).
- Abspielbarkeit wird je Datei durch echtes Öffnen geprüft: AVFoundation oder VLCKit; nicht abspielbare Dateien sind markiert und zeigen eine klare Meldung.
- Player-Fenster: Wiedergabe/Pause, Zeitleiste mit Kapitelmarken und Vorschauzeit, Sprünge (5/10/15/30/60 s, ⇧ = 60 s), Lautstärke/Ton aus, Geschwindigkeit 0,5×–2×, Ton- und Untertitelspuren, externe Untertitel (automatisch gefunden oder geladen), Kapitelmenü, Vollbild, externe Bildschirme, Vorheriger/Nächster Film, Zufall, Wiederholen, automatisch nächster Film.
- Weiterschauen mit Rückfrage (oder immer/nie), gesehen-Markierung am Ende, Statistik.
- Glas-Steuerung blendet sich nach 3 s (einstellbar) mitsamt Mauszeiger aus.
- Auswerfen während der Wiedergabe: Position gesichert, Meldung statt Absturz.

## Metadaten und Titelbilder
- Angezeigt: Titel, Dateiname, Ordner, Speicherort, Format, Größe, Auflösung (+ Klasse SD/HD/Full HD/4K/8K), Seitenverhältnis, Bildrate, Video-/Audiocodec, Datenrate, Laufzeit, Ton-/Untertitelspuren, Kapitel, Datumsangaben, zuletzt abgespielt, Wiedergaben, Fortschritt, Engine.
- Titelbilder: Posterdatei im Ordner, eingebettetes Cover, Bild aus dem Video, zuletzt gesehenes Bild – lokal, offline.
- Titel aus dem Dateinamen bereinigt (z. B. Release-Kennzeichen entfernt) oder vollständiger Dateiname.

## Ansichten, Suche, Filter
- Übersicht mit Kinobild, Statusleiste, Reihen (Weiterschauen, Neu hinzugefügt, Favoriten) und Karten (Bibliothek, Wiedergabe, Formate, Speicherorte).
- Große Poster, kompakte Poster, Liste mit sortierbaren Spalten; Kacheln 16:9 oder 2:3.
- Bereiche: Alle Filme, Weiterschauen (nicht beendet), Zuletzt hinzugefügt, Zuletzt abgespielt, Favoriten, Nicht verfügbar, Sammlungen, Speicherorte, Ordner.
- Suche über Titel, Dateiname, Endung, Ordner, Speicherort und technische Angaben; mehrere Wörter = UND, „-wort“ schließt aus, "…" für zusammenhängenden Text.
- Filter: Speicherort, Format, Auflösung, Größe, Laufzeit, Favoriten, Wiedergabestatus, Verfügbarkeit – kombinierbar, als Chips entfernbar.
- Sortierung: Titel, Dateiname, Hinzugefügt, Geändert, Größe, Laufzeit, Auflösung, Zuletzt abgespielt, Format.

## Bedienung (macOS)
- Menüleiste mit Tastaturkurzbefehlen, Kontextmenüs, Mehrfachauswahl (⌘/⇧-Klick, ⌘A), Pfeiltasten, Ziehen aus dem Finder, Vollbild.
- Einstellungen (⌘,): Darstellung, Bibliothek, Speicherorte, Durchsuchen, Wiedergabe, Tastaturkurzbefehle, Datenschutz, Über.
- Hell/Dunkel/System; echtes Liquid Glass ab macOS 26, Nachbildung auf macOS 13–15.

## Datenschutz
- Keine Konten, keine Cloud, kein Server, keine Telemetrie, keine Netzwerkberechtigung, keine kostenpflichtigen Dienste.
- Daten lokal in SQLite im Container der App.
