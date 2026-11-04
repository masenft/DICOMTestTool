# Changelog

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
