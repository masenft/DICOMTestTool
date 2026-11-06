# Changelog

## 1.4.2

### Windows
- Deutlich kleiner: portable Version 88 MB statt 205 MB, Setup 46 MB statt 73 MB, installiert 82 MB statt 152 MB (ungenutzter Code wird beim Bauen entfernt)
- Noch schnellerer Start und weniger Arbeitsspeicher
- Behoben: Das Menü des Symbols im Infobereich wurde bei jeder Statusänderung neu erzeugt; jetzt wird es nur aktualisiert
- Interner UI-Test, der bei jedem Build unter Windows alle Seiten und Dialoge prüft

### macOS
- Keine Änderungen (gemeinsames Release mit Windows)

## 1.4.1

### Windows
- Deutlich schnellerer Start: vorkompilierter Code (ReadyToRun) und keine komprimierte Einzeldatei mehr – im Test unter Windows rund dreimal schneller bis zum Fenster, rund 40 % weniger Arbeitsspeicher
- Weniger Prozessorlast im Leerlauf: ausgeblendete Fortschrittsanzeigen (Echo, Query/Retrieve, Worklist, Updates) animierten im Hintergrund weiter
- Die installierte Version liegt jetzt als normaler Programmordner vor (kein Entpacken bei jedem Start)

### macOS
- Keine Änderungen (gemeinsames Release mit Windows)

## 1.4.0

Erste Version für **Windows**.

### Windows (neu)
- **DICOM Test Tool für Windows** – dieselben Werkzeuge wie auf dem Mac: Knoten, Echo, Store (mit Testbildern), Query/Retrieve (C-FIND/C-MOVE), Worklist, Storage SCP, Watchdog und Viewer/Tag-Dump
- Viewer dekodiert zusätzlich JPEG Lossless, JPEG-LS und RLE
- Symbol im Infobereich mit Schnellzugriff (SCP, Watchdog, Echo), Windows-Benachrichtigungen, Start bei Anmeldung
- Installation per Setup ohne Administratorrechte, automatische Updates über GitHub-Releases
- Farbschemata „Standard (Windows)“ und „Klinik Dunkel“
- Hinweise zu Datenschutz, Zweckbestimmung (nicht für diagnostische Zwecke) und Marken wie auf dem Mac

### macOS
- Update-Prüfung berücksichtigt nur Releases mit macOS-Archiv (`DICOM-Test-Tool.zip`); Windows-Dateien im selben Release werden ignoriert

## 1.3.0

### Neu
- **Über › Datenschutz**: welche Daten die App speichert, welche Verbindungen sie aufbaut (nur eigene DICOM-Knoten und GitHub für Updates), keine Telemetrie
- **Über › Zweckbestimmung & rechtliche Hinweise**: Werkzeug für IT und Verbindungstests, kein Medizinprodukt, nicht für diagnostische Zwecke; keine Zertifizierung; Markenhinweis DICOM®/NEMA
- Viewer: Hinweis, dass die Bildanzeige nur der technischen Kontrolle dient
- Englische README und Projekt-Website (Englisch/Deutsch) unter masenft.github.io/DICOMTestTool

## 1.2.1

### Behoben
- Absturz in der Einführung, wenn auf der ersten Seite die Pfeiltaste ← (Zurück) mehrfach schnell gedrückt wurde
- Menüleisten-Menü öffnete sich nicht, solange ein anderes Programm aktiv war (nur grau hinterlegtes Symbol)

## 1.2.0

### Neu
- Datumsfelder (Query/Retrieve, Worklist) mit Kalender beim Hineinklicken; Eingabe weiterhin per Tastatur (TT.MM.JJJJ oder JJJJMMTT, Zeiträume mit „-“), Schnellwahl Heute, Gestern, letzte 7/30 Tage
- Geführte Einführung durch alle Werkzeuge – im Menüleisten-Menü unter „Einführung …“, unter „Über“ und im Hilfe-Menü; erscheint beim ersten Start automatisch
- Farbschema wählbar (Allgemein › Darstellung): „Standard (macOS)“ oder „Klinik Dunkel (Schwarz/Orange)“, jederzeit umschaltbar
- Store › Testbilder: Geburtsdatum mit Kalender und Eingabe als TTMMJJJJ; alle Datumsfelder zeigen das Datum als TT.MM.JJJJ
- Installation per DMG: Programm-Symbol einfach auf den Ordner „Programme“ ziehen
- Seite **Über** neu gestaltet: Updates (Update-Kanal Stabil/Vorabversionen), Einführung sowie Daten & Zurücksetzen (Datenordner, Protokolle, Zurücksetzen) an einem Ort

### Behoben
- „Berechtigung anfragen“ und „Test-Mitteilung“ ohne Reaktion: Ergebnis wird jetzt angezeigt; bei abgelehnten Mitteilungen erscheint ein Hinweis mit Link zu den Systemeinstellungen
- Fenster ließen sich über die Menüleiste nicht öffnen, wenn ein anderes Programm im Vollbild lief

## 1.1.0

### Neu
- Menüleisten-Symbol mit Schnellzugriff: SCP und Watchdog starten/stoppen, Echo an jeden Knoten, alle Werkzeuge direkt öffnen
- Bereich **Allgemein**: Start bei Anmeldung, Dock-/Menüleisten-Symbol, Popup-Hinweise für Watchdog und SCP-Empfang, Autostart von SCP und Watchdog
- Bereich **System-Tools**: App-Datenordner, Log-Dateien anzeigen (30 Tage Aufbewahrung), Zurücksetzen auf Standard
- Bereich **Updates**: automatische Suche über GitHub-Releases, Fenster mit Neuerungen, Installation mit SHA-256- und Signaturprüfung
- Bereich **Über** mit Version und Entwicklerinformationen
- Protokoll als TXT exportieren
- Neues App-Icon

## 1.0.0
- Erste Version: Echo, Store, Query/Retrieve (C-FIND/C-MOVE), Worklist, Storage SCP, Watchdog, Viewer, dicomcli
