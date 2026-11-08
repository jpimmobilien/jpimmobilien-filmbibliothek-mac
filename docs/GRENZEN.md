# Bekannte Grenzen und offene Punkte

## Signierung und Beglaubigung
- Die DMG und die App sind **ad-hoc signiert**, nicht mit einem Apple-Developer-ID-Zertifikat, und **nicht von
  Apple beglaubigt (notarisiert)**. Dafür ist ein kostenpflichtiges Apple-Entwicklerkonto nötig, das hier nicht
  vorliegt. Folge: Beim ersten Start fragt macOS nach (Vorgehen siehe „Installation – bitte lesen.txt“).
- Die Bau-Kette kann signieren und beglaubigen, sobald die Zugangsdaten als GitHub-Secrets hinterlegt sind
  (`MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD`).
- Ohne Developer-ID kann macOS nach einem App-Update gespeicherte Ordnerfreigaben eventuell nicht mehr der neuen
  Version zuordnen; die App zeigt dann „Kein Zugriff“ mit „Zugriff erteilen …“ (Daten bleiben erhalten).

## Formate
- AVFoundation spielt nur Apple-Container (MP4, M4V, MOV, 3GP) mit von macOS unterstützten Codecs.
- Alle übrigen Formate (MKV, AVI, WMV, MPG, MPEG, TS, MTS, M2TS, WEBM, FLV) spielt VLCKit. Geprüft mit je einer
  selbst erzeugten Testdatei pro Format (Codecs: siehe Testbericht). Exotische Codecs oder DRM-geschützte Dateien
  können trotzdem scheitern – die App zeigt dann „Nicht abspielbar“ bzw. eine Meldung im Player.
- Kapitel von MKV-Dateien zeigt VLCKit erst während der Wiedergabe (die Detailseite nennt dort „beim Abspielen“).
- Eingebettete Cover in MKV-Anhängen werden nicht gelesen (stattdessen Bild aus dem Video).
- HDR-Videos werden je nach Engine und Bildschirm ggf. als SDR dargestellt.

## Funktionen
- **Keine Online-Metadaten** (Plakate, Beschreibungen aus Filmdatenbanken): Die App hat bewusst keine
  Netzwerkberechtigung; kostenlose Datenbanken wie TMDb verlangen einen persönlichen API-Schlüssel.
- Bewusst nicht übernommen aus Android: Löschen/Papierkorb, Umbenennen, Verschieben zwischen Speichern, Schneiden,
  Duplikate löschen, Bild-in-Bild (Begründung: ANALYSE.md). Die App hat nur Lesezugriff.
- Keine automatische Live-Überwachung von Ordneränderungen (FSEvents): neue Dateien erscheinen beim nächsten
  Durchsuchen (beim Start, beim Anschließen eines Laufwerks oder mit ⌘R).
- Netzlaufwerke werden nicht selbst verbunden; „Verbinden“ übergibt die Adresse an den Finder (Zugangsdaten aus dem
  Schlüsselbund).

## Darstellung
- Echtes Liquid Glass gibt es nur auf macOS 26 (Tahoe) und nur, wenn die App mit dem macOS-26-SDK gebaut wurde (so
  in der CI). Auf macOS 13–15 ist es mit den Glasmaterialien von macOS nachgebildet.
- Die App ist deutsch; keine weiteren Sprachen.

## Nicht auf echter Hardware geprüft
Siehe TESTBERICHT.md, Abschnitt „Nicht geprüft“: Bedienung von Hand, echte USB-Sticks, SD-Karten, externe SSDs,
NAS/SMB, macOS 13 und 14, externe Bildschirme, Ruhezustand/Aufwachen, sehr große reale Sammlungen.
