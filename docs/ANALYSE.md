# Phase 1 – Analyse der Android-App und Übertragung auf macOS

Grundlage: Android-Projekt *Filmbibliothek 7.4.2* (Kotlin, Jetpack Compose, Room, Media3/ExoPlayer) sowie die
beiden Mac-Apps desselben Nutzers (*Music Library*, *PhotoFlow*), deren Bau-Kette übernommen wurde
(Swift-Paket → Universal-App → DMG, gebaut und geprüft mit GitHub Actions auf echten Macs).

## Funktionen der Android-App und Entscheidung für macOS

| Android-Funktion | macOS | Begründung / Umsetzung |
|---|---|---|
| Bibliothek aller Videos (MediaStore + SAF-Ordner) | ✅ übernommen, neu gebaut | Speicherorte (Ordner/ganze Laufwerke) mit sicherheitsgeschützten Lesezeichen, eigener Scanner mit Index |
| Kachel- und Listenansicht | ✅ erweitert | Große Poster, kompakte Poster, Liste; Kacheln wahlweise 16:9 oder 2:3 |
| UND-Suche + Ausschlusssuche | ✅ übernommen | Gleiche Regeln (NFC, Groß-/Kleinschreibung egal); Ausschluss jetzt mit „-wort“ im selben Feld, Anführungszeichen für zusammenhängenden Text; durchsucht Titel, Dateiname, Endung, Ordner, Speicherort, Codecs, Auflösung |
| Sortierung (Name, Größe, Datum, zuletzt abgespielt) | ✅ erweitert | + Laufzeit, Auflösung, Format, Dateiname, Änderungsdatum; natürliche Sortierung („Folge 2“ vor „Folge 10“) |
| Filter (Favoriten, gesehen, Größe, Auflösung, Speicherort) | ✅ erweitert | + Format, Laufzeit, Wiedergabestatus, Verfügbarkeit; als entfernbare Chips |
| Favoriten (Herz) | ✅ übernommen | + optional „Heart“ im Dateinamen (Android 7.3), nur lesend erkannt |
| Gesehen-Markierung, Weiterschauen | ✅ übernommen | Regeln aus `PlayerLogic.Resume`: ab 10 s, nicht in den letzten 15 s bzw. 3 %, ersetzte Datei (andere Größe) → von vorn |
| Zuletzt abgespielt + Wiedergabestatistik | ✅ übernommen | Verlauf in SQLite; „abgespielt“ zählt nach 3 s tatsächlicher Wiedergabe (Android 7) |
| Sammlungen | ✅ übernommen | Seitenleiste „Sammlungen“, Kontextmenü „Zur Sammlung hinzufügen“ |
| Ordneransicht | ✅ übernommen | Ordner eines Speicherorts mit Brotkrumen-Chips |
| Informationen | ✅ erweitert | Detailseite mit Karten: Video, Ton/Untertitel/Kapitel, Datei, Wiedergabe |
| Titelbild = zuletzt gesehenes Bild | ✅ übernommen | Nur wenn kein Poster/eingebettetes Cover existiert (abschaltbar) |
| Integrierter Player: ±20 s, Geschwindigkeit, Ton-/Untertitelspuren, externe Untertitel, Vollbild | ✅ übernommen, an macOS angepasst | Tastatur statt Gesten (←/→, Leertaste, F …), Sprungweite einstellbar, Kapitel, Glas-Kapsel |
| Warteschlange, Zufall, Wiederholen, Vorheriges/Nächstes | ✅ übernommen | Logik aus `PlayQueue`/`QueuePlanner` (Zufall behält aktuellen Film vorn) |
| Bild-in-Bild | ➖ nicht übernommen | Auf dem Mac ist ein frei verschiebbares Player-Fenster üblich; macOS-PiP wäre nur für AVFoundation möglich, nicht für VLCKit |
| Papierkorb, Löschen | ➖ bewusst nicht | Die App liest nur (Sandbox „nur lesen“); Löschen erledigt der Finder |
| Umbenennen | ➖ bewusst nicht | dito – keine Schreibrechte, keine Gefahr für Dateien |
| Verschieben intern ↔ SD-Karte (7.4–7.4.2) | ➖ bewusst nicht | Android-spezifisch (MediaStore/SD-Hauptverzeichnis); auf dem Mac Finder |
| Videos schneiden | ➖ bewusst nicht | Bearbeitung gehört nicht in eine reine Bibliothek ohne Schreibrechte |
| Duplikate finden und löschen | ➖ nicht in Version 1 | Erfordert Hash über ganze Dateien (langsam auf NAS) und Löschrechte |
| Speicherinformationen | ✅ übernommen | Belegung je Laufwerk auf den Speicherort-Karten |
| Android-Berechtigungen (MediaStore, SAF, „Alle Dateien“) | ➖ ersetzt | macOS: App-Sandbox, NSOpenPanel/Ziehen, Lesezeichen |
| Glas-Design, Hell/Dunkel/System | ✅ neu gestaltet | Liquid Glass (macOS 26) bzw. Nachbildung; Gestaltung nach den Vorlagen des Nutzers |

## Neu für macOS (Anforderungen des Auftrags)

- Laufwerke an der Volume-UUID (bzw. Freigabe-Adresse, Fingerabdruck) wiedererkennen, auch unter anderem Namen/Einhängepunkt.
- Nicht verfügbare Laufwerke: Filme bleiben mit Cover und Metadaten, Markierung „Nicht verfügbar“.
- Auswerfen während Durchsuchen bzw. Wiedergabe ohne Absturz; nichts wird dabei als „fehlend“ markiert.
- Hybrid-Wiedergabe AVFoundation + VLCKit für alle 13 geforderten Formate.
- Menüleiste, Kontextmenüs, Ziehen aus dem Finder, Dock-Symbol, Tastaturkurzbefehle, Vollbild, externe Bildschirme.

## Gestaltung (Vorgabe des Nutzers per Bildschirmaufnahme)

Vorlagen: die Mac-App „AETHER“ (macOS 13.7, Intel) und Apples MacBook-Pro-Produktseite. Übernommen:
tiefer Indigo-Verlauf mit Lichtinseln, schwebende abgerundete Glas-Seitenleiste, Versal-Abschnittsüberschriften,
blau getönte Auswahl-Pille, große fette Titel mit grauer Unterzeile, Glas-Karten mit feiner Lichtkante und
farbigem Symbol, Chips mit Farbpunkt, Kapselknöpfe (Glas bzw. Apple-Blau), Hinweisleiste mit Schild-Symbol,
Live-Statuszeile unten in der Seitenleiste; von der Produktseite: Kinobild mit sehr großer Typografie und
schwebende Glas-Kapsel als Player-Steuerung.
