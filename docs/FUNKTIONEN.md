# Funktionsliste – Filmbibliothek für macOS 1.1

Stand der Prüfung je Funktion: siehe [TESTBERICHT.md](TESTBERICHT.md).

## Bibliothek
- Speicherorte: Ordner oder ganze Laufwerke – interne SSD, externe SSD/HDD, USB-Sticks, SD-Karten, weitere Volumes, NAS/Netzlaufwerke (vorher im Finder verbunden).
- Angeschlossen oder nicht (1.1): erkannt über Laufwerkskennung, Name, Volume-UUID im Lesezeichen und Einhängepunkt; die interne SSD
  (auch das versteckte Daten-Volume) gilt immer als angeschlossen. Ist ein Laufwerk da, die gespeicherte Freigabe aber abgelaufen (z. B.
  nach einer neuen App-Version), heißt es „Kein Zugriff“ statt „Nicht verfügbar“ – „Freigaben erneuern …“ auf „Start“ lässt alle
  betroffenen Ordner nacheinander bestätigen; Bibliothek, Favoriten und Fortschritt bleiben erhalten.
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

## Gestaltung und Bewegung (1.1)
- Aufbau wie die Musikbibliothek: schwebende Glas-Navigation oben mit gleitender Linse – Start · Filme · Weiterschauen ·
  Neu · Favoriten · Sammlungen · Speicherorte (⇧⌘1–7); in schmalen Fenstern nur Symbole, immer frei von den Fensterknöpfen.
- Seitenkopf: großer Titel, Glas-Werkzeugkapsel (Ansicht, Sortierung mit Richtung, Filter, Zufallsfilm, Speicherort, Einstellungen),
  breites Suchfeld mit Fokus-Leuchten, Anzahl, Segment-Chips („Nicht beendet | Zuletzt abgespielt“, „Alle | Nicht verfügbar“, Formate).
- Mini-Player unten, solange ein Film läuft (Aufbau wie in der Musikbibliothek): großes Titelbild, Titel, Eckdaten in der Akzentfarbe
  (Jahr · Auflösung · Laufzeit), Speicherort/Ordner/Format/Engine und Position in der Warteschlange; Zeitleiste mit Zeit-Vorschau und
  Kapitelmarken; darunter Lautstärke, in der Mitte Sprünge, Wiedergabe/Pause, vorheriger/nächster Film, rechts Tempo; oben Favorit,
  Ton/Untertitel, „Player zeigen“, Beenden. In schmalen Fenstern rückt alles enger zusammen.
- Fensterhintergrund in der Farbe des laufenden Films bzw. des Kinobilds (Leitfarbe lokal aus dem Titelbild berechnet, zwischengespeichert).
- Poster-Karten: Tiefe, Kontakt- und Farbschatten, Glanzkante; beim Darüberfahren minimale Vergrößerung, wandernder Lichtreflex,
  leichte Neigung zur Maus, Schleier mit Abspielen und Restzeit, Herz zum Favorisieren (mit Puls); „NEU“-Marke (7 Tage, nie abgespielt);
  Fortschritt als Verlauf; gestaffeltes Einblenden nur für sichtbare Karten nach einem Wechsel.
- Kinobild auf „Start“: weichgezeichneter Cover-Hintergrund, Plakat mit Tiefe, Eckdaten, Fortschritt, Abspielen, Details, Favorit.
- Detailseite: Plakat wächst beim Öffnen heraus, Angaben folgen; Bildqualitäts-Anzeige (SD · HD · Full HD · 4K · 8K).
- Player: Wiedergabe/Pause gehen ineinander über, großer Knopf bei Pause, Zeitleiste mit Verlauf und Leuchten, Glas-Lautstärke.
  Steuerung, Titel oben und die Fensterknöpfe blenden sich nach 5 s ohne Maus- oder Tastatureingabe aus (einstellbar:
  2/3/5/8 s), der Mauszeiger ebenso; eine Mausbewegung oder Taste holt sie zurück. Beim Ziehen in der Zeitleiste und
  bei Pause bleiben sie sichtbar.
- Sammlungen als eigener Bereich mit Cover-Mosaik; Durchsuchen/Analyse als Glas-Kapsel mit echten Zahlen.
- Leerzustand mit App-Symbol über einem langsam laufenden Filmstreifen; Inhalt blendet beim Start einmal weich ein.
- „Bewegung reduzieren“ (macOS) und „Leichte Effekte“ (Einstellungen; Voreinstellung auf Intel-Macs mit integrierter Grafik)
  schalten Neigung, Lichtreflexe, Morphing und Staffelung ab. Keine Dauer-Animationen, keine Zeitgeber für Effekte.
- Neues App-Symbol (violetter Ordner mit Filmstreifen), Akzentfarbe Violett, DMG-Hintergrund passend.

## Ansichten, Suche, Filter
- Übersicht mit Kinobild, Statusleiste, Reihen (Weiterschauen, Neu hinzugefügt, Favoriten) und Karten (Bibliothek, Wiedergabe, Formate, Speicherorte).
- Große Poster, kompakte Poster, Liste mit sortierbaren Spalten; Kacheln 16:9 oder 2:3.
- Bereiche: Alle Filme, Weiterschauen (nicht beendet), Zuletzt hinzugefügt, Zuletzt abgespielt, Favoriten, Nicht verfügbar, Sammlungen, Speicherorte, Ordner.
- Suche über Titel, Dateiname, Endung, Ordner, Speicherort und technische Angaben; mehrere Wörter = UND, „-wort“ schließt aus, "…" für zusammenhängenden Text.
- Format-Chips mit Anzahl über der Liste („Alle 22 · MP4 7 · MKV 3 …“) – ein Klick filtert nach dem Format.
- Filter: Speicherort, Format, Auflösung, Größe, Laufzeit, Favoriten, Wiedergabestatus, Verfügbarkeit – kombinierbar, als Chips entfernbar.
- Sortierung: Titel, Dateiname, Hinzugefügt, Geändert, Größe, Laufzeit, Auflösung, Zuletzt abgespielt, Format.

## Bedienung (macOS)
- Menüleiste mit Tastaturkurzbefehlen, Kontextmenüs, Mehrfachauswahl (⌘/⇧-Klick, ⌘A), Pfeiltasten, Ziehen aus dem Finder, Vollbild.
- Einstellungen (⌘,): Darstellung, Bibliothek, Speicherorte, Durchsuchen, Wiedergabe, Tastaturkurzbefehle, Datenschutz, Über.
- Hell/Dunkel/System; echtes Liquid Glass ab macOS 26, Nachbildung auf macOS 13–15.

## Datenschutz
- Keine Konten, keine Cloud, kein Server, keine Telemetrie, keine Netzwerkberechtigung, keine kostenpflichtigen Dienste.
- Daten lokal in SQLite im Container der App.
