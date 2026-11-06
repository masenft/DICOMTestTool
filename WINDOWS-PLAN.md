# Umsetzungsplan: DICOM Test Tool für Windows

Stand: 06.11.2026 · Status: **umgesetzt** in Version 1.4.0 (zuvor Vorabversion 1.4.0-beta.1) (Code in `windows/`, Entwicklerhinweise in [windows/README.md](windows/README.md))

> Abweichungen vom Entwurf: Avalonia **11.3** statt 12 (ausgereifte, gut dokumentierte Version); Plattformteile (Toasts, Autostart) liegen direkt im App-Projekt statt in einem eigenen `Platform`-Projekt. Zusätzlich gibt es einen Selbsttest (`DICOMTestTool.exe --selftest`), der in GitHub Actions unter Windows läuft. Velopack baut das Setup direkt auf dem Mac (in Phase 0 bestätigt).

Ziel: eine Windows-Version des „DICOM Test Tool“, die sich so anfühlt und verhält wie die macOS-App 1.3.0. Entwickelt wird auf dem Mac mit Claude Code, getestet auf einem Windows-PC des Nutzers. Wie bisher ein privates, nicht-kommerzielles Open-Source-Projekt unter MIT.

---

## 1. Kurzfassung

- **Empfehlung: .NET 10 (LTS) + Avalonia UI + fo-dicom.** Gebaut auf dem Mac mit `dotnet publish -r win-x64`, verteilt als Setup-EXE über **Velopack**, Updates aus denselben **GitHub Releases** wie die Mac-App.
- **.NET 8 nicht mehr nehmen:** Der Support für .NET 8 endet am **10.11.2026**, also in wenigen Tagen. .NET 10 ist die aktuelle LTS-Version (Support bis November 2028).
- **WinUI 3 scheidet aus**, weil sich der XAML-Compiler und das Windows App SDK nur unter Windows bauen lassen. Avalonia baut auf dem Mac und läuft dort sogar. Damit kann man fast die ganze Oberfläche auf dem Mac entwickeln und testen.
- **Swift für Windows ist möglich, aber riskant:** Nur etwa 35 % des Codes wären übertragbar (DicomCore ohne Netzwerk und Bilddarstellung). Für SwiftUI gibt es unter Windows keinen Ersatz, und von macOS aus lässt sich praktisch nicht für Windows bauen.
- **Version 1 enthält alle sieben Werkzeuge** (Echo, Store, Find/Move, Worklist, SCP, Watchdog, Viewer), dazu Protokoll, Infobereich-Symbol, Benachrichtigungen, Autostart, Updates und die Seite „Über“ mit allen rechtlichen Hinweisen. Später folgen die Einführungstour, `dicomcli` für Windows und das Code-Signing.
- **Wichtig vor dem ersten Windows-Release:** Der Mac-Updater (1.1–1.3) nimmt die *erste* `.zip`-Datei eines Releases, in deren Namen „dicom“ vorkommt. Eine Windows-ZIP im selben Release würde ihn kaputtmachen (siehe Abschnitt 7.3).

---

## 2. Bestandsaufnahme der macOS-Codebasis

| Bereich | Datei(en) | Zeilen | Plattformbindung | Unter Windows |
|---|---|---:|---|---|
| Datenmodell, Tags, VR, UIDs, Transfer Syntaxes, SOP-Klassen | `DicomCore/Basics.swift`, `Dictionary.swift` | 611 | nur Foundation | Logik übertragbar; mit fo-dicom überflüssig |
| Datensätze, Part-10-Dateien, Implicit↔Explicit | `DataSet.swift` | 397 | nur Foundation | wie oben |
| PDU, Assoziation, DIMSE | `PDU.swift`, `Association.swift` | 438 | **Network.framework** (`NWConnection`) | neu schreiben (Swift) bzw. fo-dicom |
| SCU (Echo, Find, Move, Store) | `SCU.swift` | 285 | nur Foundation (über `Association`) | Abläufe als Vorlage |
| Storage SCP | `SCP.swift` | 187 | **Network.framework** (`NWListener`) | neu schreiben bzw. fo-dicom |
| Bilddarstellung | `DicomImage.swift` | 147 | **CoreGraphics, ImageIO** (JPEG/J2K) | neu schreiben bzw. fo-dicom + Codecs |
| Testbild-Generator | `TestImage.swift` | 91 | nur Foundation | 1:1 portieren (klein) |
| App-Zustand, Einstellungen, Logs, Watchdog, Autostart, Mitteilungen | `App.swift` | 630 | SwiftUI, AppKit, `UserDefaults`, `SMAppService`, `UserNotifications` | neu schreiben, Logik als Vorlage |
| Oberfläche (Werkzeuge, Datumsfelder, Theme, Tour) | `*Views.swift`, `ContentView`, `DateField`, `Theme`, `TourView` | 1.756 | SwiftUI | neu schreiben |
| Menüleiste | `MenuBarController.swift` | 133 | AppKit `NSStatusItem` | als Symbol im Infobereich (Tray) neu |
| Updater | `Updater.swift` | 310 | AppKit, CryptoKit, `ditto`, `codesign` | durch Velopack ersetzen; GitHub-Logik als Vorlage |
| Screenshot-Hook für die Website | `SnapshotHook.swift` | 132 | AppKit | später, optional |
| CLI | `dicomcli/main.swift` | 133 | über DicomCore | später, optional |

**Insgesamt 5.652 Zeilen Swift.** Davon sind etwa 2.000 Zeilen (DicomCore ohne Netzwerk und Bild) plattformneutral. Die Oberfläche mit rund 3.400 Zeilen muss auf jedem Weg neu geschrieben werden.

**Übernehmen lässt sich auf jedem Weg:**
- die Aufteilung in Werkzeuge (`Tool`-Enum: Knoten, Echo, Store, Find, Worklist, SCP, Watchdog, Viewer, Allgemein, Über), alle deutschen Texte und Bezeichnungen,
- die Bedien- und Ablauflogik: Drill-down Patient → Studie → Serie → Bild, C-MOVE-Ziel, Watchdog-Intervall mit Meldung bei Ausfall und Wiederherstellung, SCP-Ablage nach Patienten-ID, Datumseingabe `TTMMJJJJ` / `TT.MM.JJJJ` / Zeiträume mit „-“,
- Protokollformat und Log-Aufbewahrung (30 Tage), Einstellungsschlüssel (`callingAE`, `timeout`, `scpAE`, `scpPort`, `scpAnyAE`, `scpDir`, `watchInterval` …),
- Texte zu Datenschutz, Zweckbestimmung und Marken, das Icon (`Resources/AppIcon.png` → `.ico`), Changelog-Logik, Website,
- **die Mac-App selbst** als Referenz und Gegenstelle für Tests (Mac-SCP ↔ Windows-SCU und umgekehrt).

---

## 3. Vergleich der beiden Wege

### Weg 1: .NET 10 + Avalonia (oder WinUI) + fo-dicom

**Bausteine**
- **.NET 10 LTS**, C#. Self-contained Publish für `win-x64` (optional `win-arm64`) direkt auf dem Mac: `dotnet publish -c Release -r win-x64 --self-contained -p:PublishSingleFile=true`.
- **Avalonia 11/12** (MIT-Lizenz) mit Fluent-Theme in Hell und Dunkel; eigenes Theme „Klinik Dunkel“ möglich. Mit dabei: Infobereich-Symbol (`TrayIcon`), Drag & Drop, `CalendarDatePicker`, DataGrid.
- **fo-dicom 5.x** (Microsoft Public License, MS-PL): C-ECHO/FIND/MOVE/STORE, Worklist, `DicomServer` als SCP, Part-10-Lesen und -Schreiben, Transcoder (Implicit ↔ Explicit, Komprimierung), Rendering mit Fensterung. Ausgereift und weit verbreitet.
- **fo-dicom.Codecs** (native Codecs für Windows x64): JPEG Baseline/Lossless, JPEG-LS, JPEG 2000, RLE. Damit kann der Viewer **mehr als die Mac-Version** (dort fehlen JPEG Lossless, JPEG-LS und RLE).

**Avalonia oder WinUI 3?**

| | Avalonia | WinUI 3 |
|---|---|---|
| Bauen auf dem Mac | ja | **nein** (XAML-Compiler, Windows App SDK und MSIX-Werkzeuge nur unter Windows) |
| Laufen auf dem Mac (UI-Entwicklung ohne PC) | ja, mit `dotnet run` | nein |
| Aussehen unter Windows 11 | Fluent-Theme, sehr nah an nativ | 100 % nativ |
| Tray, Toasts, Autostart | Tray eingebaut; Toasts und Autostart über Windows-APIs | Toasts nativ, Tray nur über Zusatzbibliothek |
| Claude Code kann bauen und testen | vollständig auf dem Mac | nur mit Windows-Rechner oder CI |

→ **Avalonia.** Der kleine Unterschied zum „echten“ Windows-11-Aussehen ist den Entwicklungsablauf auf dem Mac wert.

**Eigene DicomCore nach C# portieren statt fo-dicom?** Das ginge (rund 2.200 Zeilen). Man hätte dann genau dieselben Protokollausgaben wie auf dem Mac, müsste aber Netzwerk, Codecs und Fehlerfälle selbst pflegen. **Empfehlung: fo-dicom nehmen.** Das Protokoll (Presentation-Context-Aushandlung, Zeitmessung) bauen wir aus den Ereignissen und dem Logging von fo-dicom im gleichen Format nach. Nur der Testbild-Generator wird portiert.

**Vorteile:** Fast alles lässt sich auf dem Mac bauen, testen und sogar ausführen. Bewährte DICOM-Bibliothek, mehr Codecs, große Community, sehr gute Werkzeuge für Installer und Updates (Velopack), und Claude Code schreibt C# zuverlässig.
**Nachteile:** Kein Swift-Code wird wiederverwendet; zwei Codebasen müssen gepflegt werden. Die App ist größer (self-contained etwa 70–100 MB, gepackt etwa 35–45 MB). Abhängigkeit von fo-dicom (MS-PL ist mit MIT vereinbar, der Lizenzhinweis muss aber mitgeliefert werden).

### Weg 2: Swift für Windows mit einer Windows-Oberfläche

**Bausteine**
- Die offizielle Swift-6-Toolchain für Windows mit Foundation (swift-foundation).
- **Netzwerk:** `Network.framework` gibt es nicht. `DicomConnection` und `StorageSCP` müssten auf Winsock (Modul `WinSDK`) oder SwiftNIO umgestellt werden. Die Windows-Unterstützung von SwiftNIO ist weiterhin unvollständig.
- **Bild:** Ohne CoreGraphics und ImageIO braucht man eigenes Rendering und C-Bibliotheken für JPEG und JPEG 2000 (libjpeg-turbo, OpenJPEG), die für Windows gebaut und eingebunden werden müssen.
- **Updater:** Für CryptoKit gibt es `swift-crypto` als Ersatz; Installieren und Ersetzen der App müsste man selbst schreiben.
- **Oberfläche:** SwiftUI gibt es unter Windows nicht. Zur Wahl stünden `swift-winrt` mit WinUI 3 (spärlich dokumentiert, kleine Nutzerbasis, Zukunft unklar), reines Win32 über `WinSDK` (sehr aufwendig) oder GTK/Adwaita (sieht nicht nach Windows aus).
- **Bauen:** Für Windows ohne Windows-SDK von macOS aus zu kompilieren ist praktisch nicht machbar. Gebaut und debuggt wird auf dem PC oder in einer GitHub-Actions-Umgebung mit Windows.

**Vorteile:** Etwa 2.000 Zeilen DicomCore lassen sich weiterverwenden; DICOM-Logik und Protokollausgaben bleiben auf beiden Plattformen gleich.
**Nachteile:** Die Oberfläche (der größte Teil der Arbeit) muss trotzdem neu geschrieben werden, und zwar mit den schwächsten Werkzeugen. Claude Code kann auf dem Mac nichts bauen oder testen; jeder Schritt läuft über den PC oder die CI. Der Aufwand für Netzwerk, Codecs, Installer und Updater ist hoch, das Risiko ebenfalls.

### Gegenüberstellung

| Kriterium | Weg 1: .NET + Avalonia + fo-dicom | Weg 2: Swift für Windows |
|---|---|---|
| Wiederverwendeter Code | 0 % (aber Logik, Texte, Struktur) | ca. 35 % (DicomCore ohne Netzwerk und Bild) |
| Bauen auf dem Mac | **ja** | nein |
| Testen und Ausführen auf dem Mac | **ja** (UI, DICOM-Netzwerk, Unit-Tests) | nein |
| Reife der UI-Technik unter Windows | hoch | niedrig |
| DICOM-Funktionen | fo-dicom, mehr Codecs als bisher | eigene, Netzwerk und Bild neu |
| Installer und Updates | Velopack, fertig | selbst bauen |
| Geschätzter Aufwand bis 1.0 | **mittel** (ca. 15–25 Claude-Code-Sitzungen) | hoch (ca. 40+ Sitzungen, großes Risiko) |
| Pflege später | zwei Sprachen, aber jede mit Standardwerkzeugen | eine Sprache, aber Windows-Sonderwege |

### Empfehlung

**Weg 1: .NET 10 + Avalonia + fo-dicom.** Der Hauptgrund ist der Entwicklungsablauf: Claude Code kann auf dem Mac bauen, Unit- und Netzwerktests ausführen und die Oberfläche starten. Der Windows-PC wird nur für die Windows-spezifische Abnahme gebraucht. Mit Swift für Windows bliebe nur DicomCore erhalten, also der Teil, den fo-dicom ohnehin besser abdeckt.

---

## 4. Funktionsumfang der Version 1

| Werkzeug | In V1 | Hinweise für Windows |
|---|---|---|
| **Knoten & Einstellungen** | ✅ | Knotenliste, Calling AE, Timeout; Einstellungen als JSON |
| **Echo** | ✅ | Zeitmessung (Assoziation, Echo, gesamt), Wiederholungen |
| **Store** | ✅ | Dateien und Ordner per Drag & Drop aus dem Explorer; Testbild-Generator (portiert, ohne echte Patientendaten); automatische Umwandlung Implicit ↔ Explicit über den fo-dicom-Transcoder |
| **Query / Retrieve** | ✅ | C-FIND Patient/Study Root auf allen Ebenen, Drill-down per Doppelklick, C-MOVE zu beliebigem Ziel; Datumsfelder mit Kalender und Tastatureingabe wie auf dem Mac |
| **Worklist** | ✅ | MWL-Abfrage wie eine Modalität |
| **Storage SCP** | ✅ | Ablage nach Patienten-ID, beliebiger oder fester AE; **Hinweis auf die Windows-Firewall** (siehe 6.3) |
| **Watchdog** | ✅ | periodisches C-ECHO, Windows-Benachrichtigung bei Ausfall und Wiederherstellung |
| **Viewer / Tag-Dump** | ✅ | alle Tags inklusive Sequenzen mit Filter, Fensterung, Multiframe, PNG-Export; dank fo-dicom.Codecs zusätzlich JPEG Lossless, JPEG-LS und RLE; **Hinweis „nur technische Kontrolle, nicht für diagnostische Zwecke“** |
| **Protokoll** | ✅ | mit Presentation-Context-Aushandlung, Export als TXT |
| **Allgemein** | ✅ | Start bei Anmeldung, Symbol im Infobereich, „beim Schließen im Infobereich weiterlaufen“, Benachrichtigungen, Autostart von SCP und Watchdog, Datenordner und Logs öffnen, Zurücksetzen |
| **Über** | ✅ | Version, Updates (Stabil/Vorabversionen), Datenschutz, Zweckbestimmung, Marken, Drittanbieter-Lizenzen |
| Farbschema „Klinik Dunkel“ | ✅ (wenn einfach) | Fluent Hell/Dunkel folgt dem System, „Klinik Dunkel“ als eigenes Theme |
| Geführte Einführung | ⏳ 1.x | |
| `dicomcli` für Windows | ⏳ 1.x | als .NET-Konsolenprogramm mit derselben Syntax |
| Code-Signing | ⏳ sobald verfügbar | siehe 8. |
| Englische Oberfläche | ⏳ später | Texte von Anfang an in `.resx` sammeln, dann ist es später leicht |
| Nicht geplant (wie auf dem Mac) | — | DICOM Print, C-GET, TLS |

**Pflichttexte, die erhalten bleiben müssen** (wörtlich aus der Mac-App bzw. README übernehmen):
- „Nur für IT und Verbindungstests – nicht für diagnostische Zwecke.“ Kein Medizinprodukt im Sinne der MDR (EU) 2017/745; keine Zertifizierung, kein Conformance Statement.
- „DICOM® ist eine eingetragene Marke der National Electrical Manufacturers Association (NEMA) …“, nur beschreibend, keine Verbindung zur NEMA.
- Neu: „Windows ist eine Marke der Microsoft Corporation.“ (statt bzw. zusätzlich zum macOS-Hinweis)
- Privates, nicht-kommerzielles Open-Source-Projekt, MIT, ohne Gewährleistung.
- Datenschutz: keine Telemetrie; Verbindungen nur zu eigenen Knoten und zu GitHub für Updates.
- Neu: `THIRD-PARTY-NOTICES.txt` mit fo-dicom (MS-PL), fo-dicom.Codecs und den enthaltenen nativen Bibliotheken (die genauen Lizenzen beim Einbinden prüfen), Avalonia (MIT), Velopack (MIT).

Name im Startmenü: **„DICOM Test Tool“**; Website und README: „DICOM Test Tool für Windows“.

---

## 5. Architektur und Projektaufbau

Alles im bestehenden Repository, damit Website, Issues, Changelog und Releases gemeinsam bleiben:

```
windows/
  DicomTestTool.Windows.sln
  src/
    DicomTestTool.Core/      # Dienste ohne UI: Knoten, Einstellungen, Logging,
                             # Echo/Store/Find/Move/MWL/SCP/Watchdog auf fo-dicom,
                             # Testbild-Generator, Datumsparser
    DicomTestTool.App/       # Avalonia-App (MVVM mit CommunityToolkit.Mvvm),
                             # Views je Werkzeug, Tray, Themes
    DicomTestTool.Platform/  # Windows-Teile: Toasts, Autostart (HKCU\…\Run),
                             # Firewall-Hinweis; für macOS leere Stubs (Dev-Läufe)
  tests/
    DicomTestTool.Core.Tests/  # xUnit; Tests gegen einen fo-dicom-SCP im selben Prozess
  build/
    publish-win.sh           # dotnet publish + vpk pack, auf dem Mac
```

- **Ziel-Frameworks:** `Core` und `App` mit `net10.0`, `Platform` mit `net10.0-windows10.0.19041.0` und `EnableWindowsTargeting=true`, damit der Mac die Windows-APIs (Toasts) bauen kann.
- **Einstellungen:** `%APPDATA%\DICOM Test Tool\settings.json` mit denselben Schlüsseln wie auf dem Mac.
- **Logs:** `%LOCALAPPDATA%\DICOM Test Tool\Logs` (30 Tage).
- **SCP-Ablage:** standardmäßig `Dokumente\DICOM Empfang`, frei wählbar.
- **Bild-Rendering:** fo-dicom `DicomImage.RenderImage()` mit dem Raw-Image-Manager → Avalonia `WriteableBitmap`, ohne ImageSharp (Lizenz Six Labors Split License, vermeiden).
- **Nebenläufigkeit:** Alle DICOM-Abläufe sind `async`; Ergebnisse gehen über den UI-Dispatcher ans ViewModel. SCP und Watchdog laufen unabhängig vom Fenster weiter.

---

## 6. Windows-spezifische Punkte

### 6.1 Symbol im Infobereich (statt Menüleiste)
Avalonia-`TrayIcon` mit demselben Menü wie auf dem Mac: SCP und Watchdog starten/stoppen, Echo an jeden Knoten, Werkzeuge öffnen, Nach Updates suchen, Beenden. Beim Schließen des Fensters läuft die App im Infobereich weiter (einstellbar), damit SCP und Watchdog aktiv bleiben.

### 6.2 Benachrichtigungen
Windows-Toasts über das Windows App SDK bzw. das CommunityToolkit (`AppNotificationManager`/`ToastNotificationManager`). Unverpackte Apps brauchen dafür eine AppUserModelID und eine Startmenü-Verknüpfung; beides legt Velopack an. **Im Spike prüfen.** Ausweichlösung: Sprechblase des Tray-Symbols.

### 6.3 Firewall beim SCP
Beim ersten Lauschen auf einem Port fragt die Windows-Defender-Firewall nach, und die Freigabe braucht Administratorrechte. Velopack installiert ohne Administratorrechte pro Benutzer und kann deshalb keine Regel anlegen. Lösung für V1:
- Die SCP-Seite zeigt einen Hinweis und den passenden Befehl zum Kopieren (`netsh advfirewall firewall add rule … program="…" dir=in action=allow`).
- Die README beschreibt, welcher Haken im Firewall-Dialog zu setzen ist (privates bzw. Domänennetzwerk).
- Später optional: ein Knopf „Firewall-Regel anlegen“, der `netsh` mit UAC-Abfrage startet.

### 6.4 Autostart
`HKCU\Software\Microsoft\Windows\CurrentVersion\Run` mit dem Pfad, den Velopack vorgibt (der Pfad bleibt über Updates hinweg gleich). Keine Administratorrechte nötig.

### 6.5 Weitere Punkte
- Hohe DPI-Werte (125/150/200 %), Pfade mit Umlauten und Leerzeichen, in OneDrive umgeleitete Dokumente-Ordner.
- Optional: „Öffnen mit“ für `.dcm` (Dateizuordnung im Velopack-Hook), V1.x.
- Unterstützt werden **Windows 11** und **Windows 10 22H2** (letzteres ohne Gewähr, da das Supportende bereits erreicht ist), x64. `win-arm64` zusätzlich, sobald es sich ohne Mehraufwand bauen lässt.

---

## 7. Installer und Updates

### 7.1 Installer: Velopack statt MSIX für V1

| | **Velopack** (empfohlen) | MSIX |
|---|---|---|
| Ohne Signatur installierbar | ja (mit SmartScreen-Warnung) | **nein**, MSIX muss mit einem vertrauenswürdigen Zertifikat signiert sein |
| Administratorrechte | nein (pro Benutzer) | nein |
| Updates aus GitHub Releases | eingebaut (`GithubSource`), Delta-Updates | über eine `.appinstaller`-Datei oder den Store |
| Bauen auf dem Mac | `vpk [win] pack` läuft laut Doku plattformübergreifend → **im Spike prüfen**; sonst GitHub Actions mit Windows | Windows-Werkzeuge nötig |
| Firewall, Tray, Run-Key | uneingeschränkt | Einschränkungen durch den Paket-Container |

→ **V1 erscheint als Velopack-Setup** (`DICOM-Test-Tool-win-Setup.exe`, Lizenz MIT).
**MSIX kommt später über den Microsoft Store in Frage:** Seit 2025 ist das Konto für einzelne Entwickler kostenlos, und der Store signiert die Pakete selbst. Dann gibt es keine SmartScreen-Warnung und keine Zertifikatskosten. Voraussetzung sind eine Datenschutz-URL (die Website hat bereits eine) und eine Store-Zertifizierung; der Hinweis „kein Medizinprodukt“ muss im Store-Eintrag stehen. Das wird als eigener Schritt nach 1.0 geprüft.

### 7.2 Updates über GitHub Releases
- In der App: `UpdateManager` von Velopack mit `GithubSource("https://github.com/masenft/DICOMTestTool", prerelease: <Kanal>)`; Updatekanal Stabil/Vorabversionen wie auf dem Mac.
- Ablauf wie auf dem Mac: einmal täglich prüfen (abschaltbar), Fenster mit den Release Notes, „Installieren und neu starten“. Velopack prüft die SHA-256-Prüfsummen der Pakete selbst.
- Die Release Notes kommen weiterhin aus `CHANGELOG.md`. Zu prüfen ist, ob Velopack sie mitliefert; sonst holt die App sie wie auf dem Mac über die GitHub-API.

### 7.3 Gemeinsame Releases mit der Mac-App (wichtig)
Der Updater der Mac-Versionen 1.1–1.3 fragt `releases/latest` ab und nimmt **die erste `.zip`-Datei, deren Name „dicom“ enthält** (`Updater.swift`, `zipAsset`). Daraus folgt:
1. **Ein reines Windows-Release** würde zu `latest` werden. Alte Mac-Clients melden dann „Das Release enthält kein ZIP-Archiv der App“.
2. **Eine Windows-ZIP im selben Release** (z. B. Velopacks `…-Portable.zip`) könnte der Mac-Updater herunterladen. Die Signaturprüfung würde scheitern, und das Update bricht ab.

**Regeln dafür:**
- **Immer gemeinsame Releases** mit **einer** Versionsnummer für beide Plattformen (die erste Windows-Version wäre also z. B. **1.4.0**). Hat sich nur eine Plattform geändert, wird die andere trotzdem neu gebaut und angehängt.
- **Windows-Dateien ohne `.zip`:** nur `DICOM-Test-Tool-win-Setup.exe`, `*.nupkg`, `releases.win.json` (bzw. das, was Velopack braucht). Kein Portable-ZIP hochladen, oder es als `.7z` bzw. ohne „dicom“ im Namen veröffentlichen.
- **Mac 1.4.0 gleichzeitig härten:** Der Updater soll exakt `DICOM-Test-Tool.zip` verlangen und Releases ohne Mac-Datei überspringen. Die Regeln oben gelten trotzdem weiter, solange alte Mac-Versionen im Umlauf sind.
- `release.sh` wird zu einem gemeinsamen Release-Skript erweitert, das beide Builds anhängt (Windows-Build auf dem Mac oder als CI-Artefakt).
- *Alternative:* Windows-Releases in einem eigenen Repository (`masenft/DICOMTestTool-Windows`). Das entkoppelt die Plattformen vollständig, verteilt aber Issues und Website auf zwei Orte. Nur nehmen, wenn gemeinsame Releases im Alltag stören.

---

## 8. Code-Signing und SmartScreen

Ohne Signatur zeigt Windows beim ersten Start **„Der Computer wurde durch Windows geschützt“** (SmartScreen). Das entspricht der Gatekeeper-Freigabe auf dem Mac. Für V1 ist das vertretbar, wenn die README es genau beschreibt: **„Weitere Informationen“ → „Trotzdem ausführen“**. Velopack-Updates lösen die Warnung nicht erneut aus, weil sie im Hintergrund installiert werden.

Möglichkeiten für eine Signatur (für ein privates Open-Source-Projekt), nach Empfehlung geordnet:

| Möglichkeit | Kosten | Bemerkung |
|---|---|---|
| **SignPath Foundation** (kostenloses Signing für OSS-Projekte) | kostenlos | Antrag nötig; signiert in GitHub Actions nach einem reproduzierbaren CI-Build. Passt gut zum Projekt. **Erste Wahl, nach 1.0 beantragen.** |
| **Microsoft Store** (MSIX, vom Store signiert) | kostenlos | löst SmartScreen für die Store-Variante; die Velopack-Setup-Datei bliebe unsigniert |
| **Azure Artifact Signing** (früher Trusted Signing) | ca. 10 USD/Monat | Ob Privatpersonen in Deutschland zugelassen werden, beim Antrag prüfen |
| **Certum Open Source Code Signing** | ca. 30–60 €/Jahr | Cloud-Signatur (SimplySign); Ausweis-Identifizierung, zeigt den bürgerlichen Namen |

Hinweise:
- Auch signierte Dateien warnen anfangs noch, bis sich ein Ruf aufgebaut hat (OV-Zertifikate). EV-Zertifikate überspringen diese Phase nicht mehr automatisch.
- Das Signieren läuft mit `vpk pack --signTemplate` bzw. als CI-Schritt. `signtool` gibt es nur unter Windows; deshalb wird das signierte Release in GitHub Actions (`windows-latest`) gebaut, sobald es eine Signatur gibt.
- Datenschutz: Die Signatur zeigt den Namen der Person bzw. Organisation an. Das bei der Wahl der Möglichkeit bedenken.

---

## 9. Vorgehen in Phasen

| Phase | Inhalt | Ergebnis | ca. Sitzungen |
|---|---|---|---:|
| **0. Machbarkeitstest** | Lösungsgerüst; Avalonia-Fenster + fo-dicom-Echo gegen Orthanc oder die Mac-App; `dotnet publish -r win-x64` auf dem Mac; `vpk pack` auf dem Mac; auf dem PC prüfen: Start, SmartScreen, Firewall-Dialog, Toast, Tray, Velopack-Update von 0.0.1 auf 0.0.2 über ein Test-Release (Draft/Fork) | Entscheidung bestätigt; offene Punkte (Velopack auf dem Mac, Toasts) geklärt | 1–2 |
| **1. Core** | Einstellungen, Knoten, Logging; Dienste für Echo, Store (+ Transcoding), Find, Move, MWL, SCP, Watchdog; Testbild-Generator portieren; Datumsparser; xUnit-Tests mit SCP im selben Prozess | `dotnet test` grün auf dem Mac | 4–6 |
| **2. Oberfläche** | Hauptfenster mit Seitenleiste wie auf dem Mac; je Werkzeug eine View; Protokoll-Leiste; Datumsfeld; Viewer mit Fensterung und PNG-Export; Themes | App läuft auf dem Mac mit `dotnet run` vollständig | 6–9 |
| **3. Windows-Integration** | Tray, Toasts, Autostart, Firewall-Hinweis, Pfade, DPI | Abnahme auf dem PC | 2–3 |
| **4. Paket und Updates** | Velopack, Icon (`.ico`), gemeinsames Release-Skript, Härtung des Mac-Updaters (Mac 1.4.0), README- und Website-Abschnitt „Windows“, `THIRD-PARTY-NOTICES` | Release-Kandidat | 2–3 |
| **5. Test und Release** | Testplan (Abschnitt 10) auf dem PC; Vorabversion `1.4.0-beta.1` (Kanal Vorabversionen); danach `1.4.0` | erstes öffentliches Windows-Release | 1–2 |
| später | Einführungstour, `dicomcli`, Signatur (SignPath), Store/MSIX, Englisch, `.dcm`-Zuordnung, CI-Build | | |

Jede Phase endet mit einem Commit-Vorschlag. Committet und gepusht wird **nur nach Freigabe** (Autor-E-Mail `173460664+masenft@users.noreply.github.com`).

---

## 10. Testablauf auf dem Windows-PC

### 10.1 Entwicklungsschleife
1. Auf dem Mac (Claude Code): entwickeln, `dotnet test`, Oberfläche mit `dotnet run` prüfen. Die meisten Fehler zeigen sich schon hier.
2. Windows-Build auf dem Mac: `windows/build/publish-win.sh` erzeugt `dist-win/` mit der EXE (portabel) und dem Velopack-Setup.
3. **Auf den PC bringen**, je nach Wahl:
   - **SMB-Freigabe** des Mac-Ordners (Systemeinstellungen › Allgemein › Teilen › Dateifreigabe) → auf dem PC `\\<mac-name>\dist-win` öffnen. Am schnellsten für den Alltag.
   - oder **GitHub Actions**: Jeder Push auf den Windows-Branch baut auf `windows-latest`, und das Artefakt wird im Browser heruntergeladen. Das ist zugleich ein Test, ob es auch unter Windows baut.
4. Auf dem PC zunächst die **portable EXE** direkt starten. Das Setup erst testen, wenn es um Installer, Autostart oder Updates geht.
5. Bei Fehlern das Protokoll exportieren (vorher Patientendaten entfernen) oder `%LOCALAPPDATA%\DICOM Test Tool\Logs` an Claude Code geben.

Optional: Windows 11 on ARM in UTM oder Parallels auf dem Mac für schnelle Starttests (x64-Emulation). Die Abnahme bleibt aber auf dem echten PC.

### 10.2 DICOM-Gegenstellen für Tests
- **Mac-App 1.3** im selben Netz: Mac-SCP ← Windows-Store/-Move, Windows-SCP ← Mac-Store, Echo in beide Richtungen.
- **Orthanc** (Docker auf dem Mac oder Windows-Installer) als PACS für Find/Move/Store, mit Testbildern aus dem eigenen Generator.
- **DCMTK** (`storescu`, `findscu`, `echoscu`, `wlmscpfs` für die Worklist) als neutrale Referenz.
- Nur Testdaten verwenden, **keine echten Patientendaten**.

### 10.3 Abnahme-Checkliste (je Release-Kandidat)
- [ ] Installation per Setup als **normaler Benutzer** ohne Administratorrechte; SmartScreen-Ablauf wie in der README beschrieben
- [ ] Startmenü-Eintrag, Icon, Deinstallation über „Apps & Features“ (Einstellungen und Logs bleiben bzw. werden wie beschrieben entfernt)
- [ ] Echo: Erfolg, falscher AE (Ablehnung wird angezeigt), Host nicht erreichbar, Timeout
- [ ] Store: Einzeldatei, Ordner per Drag & Drop, Testbilder; Implicit-only-Gegenstelle (Umwandlung greift); komprimierte Datei an eine Gegenstelle ohne passende Syntax
- [ ] Find: alle Ebenen, Drill-down, Datumsbereiche, Platzhalter `*`; Move zur Mac-App und zum eigenen SCP
- [ ] Worklist gegen `wlmscpfs` oder Orthanc-Worklist
- [ ] SCP: Firewall-Dialog bzw. Hinweis, Empfang von Mac und DCMTK, Ablage nach Patienten-ID, Pfad mit Umlauten
- [ ] Watchdog: Knoten stoppen → Toast „nicht erreichbar“, starten → Toast „wieder erreichbar“; läuft bei geschlossenem Fenster im Tray weiter
- [ ] Viewer: unkomprimiert MONOCHROME1/2, RGB, Multiframe, JPEG, JPEG 2000, JPEG Lossless, JPEG-LS, RLE; Fensterung, PNG-Export; Hinweis „nicht für diagnostische Zwecke“ sichtbar
- [ ] Autostart nach Anmeldung, Autostart von SCP und Watchdog
- [ ] DPI 100/150/200 %, helles und dunkles Windows-Design, „Klinik Dunkel“
- [ ] Update: installierte Vorversion → neues Release auf GitHub (Vorabversionskanal) → Fenster mit Neuerungen → Installieren und neu starten → neue Version läuft, Einstellungen sind erhalten
- [ ] **Mac-Gegenprobe:** Mac 1.3 findet im gemeinsamen Release weiterhin seine ZIP und aktualisiert sich korrekt
- [ ] Seite „Über“: Datenschutz, Zweckbestimmung, DICOM®/NEMA-Hinweis, Windows-Markenhinweis, Drittanbieter-Lizenzen

---

## 11. Risiken und offene Punkte

| Risiko / Frage | Umgang |
|---|---|
| `vpk pack` für Windows auf dem Mac funktioniert nicht vollständig | Phase 0 prüft das; sonst Paketbau in GitHub Actions (`windows-latest`) |
| Toasts aus der unverpackten App | Phase 0; Ausweichlösung Tray-Sprechblase |
| fo-dicom-Kompatibilität mit .NET 10 bzw. der aktuellen Avalonia-Version | Versionen in Phase 0 festlegen; fo-dicom unterstützt `netstandard2.0`/`net6+` |
| Lizenzen der nativen Codecs (fo-dicom.Codecs) | beim Einbinden prüfen und in `THIRD-PARTY-NOTICES` aufnehmen; notfalls ohne Zusatzcodecs ausliefern (dann wie auf dem Mac) |
| Protokollausgaben weichen vom Mac ab | Protokollformat in `Core` zentral nachbauen; Vergleich mit Mac-Logs im Test |
| Mac-Updater stolpert über Windows-Dateien | Regeln aus 7.3 und Härtung in Mac 1.4.0 |
| SmartScreen schreckt Nutzer ab | klare README-Anleitung; SignPath nach 1.0 beantragen; Store prüfen |
| Doppelte Pflege zweier Codebasen | gleiche Struktur und Texte; Changelog getrennt nach „macOS“ und „Windows“ innerhalb einer Version |

**Entscheidungen, die der Nutzer treffen muss:**
1. Weg 1 (empfohlen) freigeben?
2. Gemeinsame Releases mit gemeinsamer Versionsnummer (empfohlen) oder ein eigenes Windows-Repository?
3. Übertragung auf den PC: SMB-Freigabe, GitHub-Actions-Artefakte oder beides?
4. Signatur: zunächst unsigniert mit SmartScreen-Anleitung, dann SignPath beantragen (empfohlen)?
