# DICOM Test Tool für Windows – Entwicklung

Windows-Version des DICOM Test Tool. Sie wird auf dem Mac entwickelt und gebaut; getestet wird auf einem Windows-PC. Hintergrund und Entscheidungen stehen in [WINDOWS-PLAN.md](../WINDOWS-PLAN.md).

| Baustein | Technik |
|---|---|
| Oberfläche | [Avalonia](https://avaloniaui.net) 11.3 (Fluent), läuft zum Entwickeln auch auf dem Mac |
| DICOM | [fo-dicom](https://github.com/fo-dicom/fo-dicom) 5.2 + fo-dicom.Codecs (JPEG, JPEG-LS, JPEG 2000, RLE) |
| Installer und Updates | [Velopack](https://velopack.io) – Setup ohne Administratorrechte, Updates aus GitHub-Releases |
| Benachrichtigungen | Windows-Toasts (Microsoft.Toolkit.Uwp.Notifications) |

## Aufbau

| Ordner | Inhalt |
|---|---|
| `src/DicomTestTool.Core` | DICOM-Dienste ohne Oberfläche: Echo, Store, Find, Move, Worklist, Storage SCP, Testbilder, Viewer-Rendering, Einstellungen, Protokoll, Selbsttest |
| `src/DicomTestTool` | Avalonia-App (`DICOMTestTool.exe`), Ziel-Frameworks `net10.0` (Mac zum Entwickeln) und `net10.0-windows10.0.19041.0` (Auslieferung) |
| `tests/DicomTestTool.Core.Tests` | xUnit-Tests gegen einen SCP im selben Prozess; optional Gegenprobe mit dem Mac-`dicomcli` (`DTT_MACCLI=…/dist/dicomcli`) |
| `tests/DicomTestTool.UiTests` | rendert alle Seiten headless als PNG (`DTT_SNAPSHOT_DIR`, `DTT_THEME=clinicalDark`) |
| `build/publish-win.sh` | Tests, `dotnet publish -r win-x64`, `vpk pack` → `../dist-win/` |
| `licenses/THIRD-PARTY-NOTICES.txt` | Lizenzen der Bibliotheken (wird mit ausgeliefert) |

## Auf dem Mac

Voraussetzung: .NET 10 SDK (z. B. `dotnet-install.sh --channel 10.0` nach `~/.dotnet`).

```bash
cd windows
dotnet test tests/DicomTestTool.Core.Tests          # Tests
dotnet run --project src/DicomTestTool -f net10.0   # App auf dem Mac starten
dotnet run --project src/DicomTestTool -f net10.0 -- --selftest
./build/publish-win.sh                              # Windows-Build + Setup nach ../dist-win
```

Build-Ausgaben landen außerhalb von iCloud Drive in `$TMPDIR` (siehe `Directory.Build.props`).

## Auf dem Windows-PC testen

- **Schnell:** `dist-win/DICOM-Test-Tool-win-portable.exe` auf den PC kopieren (z. B. über eine SMB-Freigabe des Macs) und direkt starten.
- **Installer und Updates:** `dist-win/DICOM-Test-Tool-win-Setup.exe` ausführen. Updates gibt es nur in der installierten Version.
- **Selbsttest:** `DICOMTestTool.exe --selftest ergebnis.txt` prüft Codecs, Storage SCP, Echo und Store gegen sich selbst.
- **CI:** Jeder Push auf `windows`/`main` baut und testet in GitHub Actions unter Windows (`.github/workflows/windows.yml`); dort lässt sich die portable EXE als Artefakt herunterladen.

Daten der App: Einstellungen in `%APPDATA%\DICOM Test Tool\settings.json`, Protokolle in `%LOCALAPPDATA%\DICOM Test Tool\Logs`.

## Release

Gemeinsam mit der Mac-Version über `../release.sh` (gleiche Versionsnummer aus `../VERSION`, Release Notes aus `../CHANGELOG.md`). Ins Release kommen nur `DICOM-Test-Tool-win-Setup.exe` und `DICOM-Test-Tool-win-portable.exe` (jeweils + `.sha256`), `DICOMTestTool-<Version>-full.nupkg`, `releases.win.json`, `assets.win.json` und `RELEASES` – **keine ZIP-Datei**, damit ältere Mac-Versionen beim Update nicht die falsche Datei nehmen.

Das Setup ist noch nicht signiert (SmartScreen-Hinweis beim ersten Start). Für eine Signatur ist `vpk pack --signTemplate` vorgesehen, siehe WINDOWS-PLAN.md, Abschnitt 8.
