<p align="center">
  <img src="Resources/AppIcon.png" width="160" alt="DICOM Test Tool for macOS icon">
</p>

<h1 align="center">DICOM Test Tool for macOS</h1>

<p align="center">
  <b>A free, native Mac app for testing and troubleshooting DICOM connections</b><br>
  C-ECHO · C-STORE · C-FIND / C-MOVE · Modality Worklist · Storage SCP · Watchdog · Tag viewer
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Apple%20Silicon%20%26%20Intel-universal-555" alt="Universal">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/License-MIT-blue" alt="MIT License">
</p>

<p align="center">
  <a href="../../releases/latest"><b>⬇️ Download the latest version (DMG)</b></a> ·
  <a href="https://masenft.github.io/DICOMTestTool/">Website</a> ·
  <a href="README.de.md">🇩🇪 Deutsche Version</a>
</p>

---

## What is it?

**DICOM Test Tool for macOS** is a free, open-source app for PACS administrators, biomedical and medical IT engineers, and IT support staff. Use it to check quickly whether PACS, RIS, modalities and workstations can talk to each other – and to find out why they can't.

It is written natively in Swift and SwiftUI and has its **own DICOM networking implementation with no third-party libraries**.

> [!WARNING]
> **For IT and connection testing only – not for diagnostic use.**
> This software is **not a medical device** under Regulation (EU) 2017/745 (MDR) or comparable regulations. It must not be used for diagnosis, reporting, treatment planning or any other clinical decision. The image display only lets you check transferred data from a technical point of view.

## Features

| Tool | What it does |
|---|---|
| 🖧 **Nodes & settings** | Manage remote nodes (AE title, host, port); your own calling AE title and timeout |
| 📡 **Echo (Verification)** | C-ECHO “DICOM ping” with timings (association, echo, total) and repeat count |
| 📤 **Store** | C-STORE files and folders via drag & drop; built-in test image generator (no real patient data); automatic Implicit ↔ Explicit VR conversion |
| 🔍 **Query / Retrieve** | C-FIND (Study / Patient Root) at patient, study, series and image level; double-click to drill down; C-MOVE to any destination |
| 📋 **Modality Worklist** | MWL query against your RIS – just like a modality would send it |
| 📥 **Storage SCP** | Turns your Mac into a DICOM receiver; files are sorted by patient ID; ideal as a C-MOVE destination |
| ❤️ **Watchdog** | Keeps monitoring nodes with C-ECHO and sends a macOS notification on failure and recovery |
| 🖼️ **Viewer / tag dump** | All tags including sequences, with filter; image display with windowing, multi-frame, JPEG / JPEG 2000, PNG export |

**Also included:**

- 📍 **Menu bar icon** – start and stop the SCP and Watchdog, send an echo, open any tool, even over full-screen apps
- 📝 **Protocol log** of every step, including presentation context negotiation, exportable as TXT
- 📅 **Date fields with a calendar** – or type `DDMMYYYY` / `DD.MM.YYYY`
- 🎓 **Guided tour** through all tools
- 🎨 **Colour schemes:** standard (macOS) or clinical dark (black / orange)
- 🔄 **Automatic updates** via GitHub Releases, with release notes plus checksum and signature checks
- 🚀 Launch at login, auto-start of the SCP and Watchdog, log files (kept 30 days)

> The user interface is currently in **German**.

## Installation

1. Download **`DICOM-Test-Tool.dmg`** from [**Releases**](../../releases/latest).
2. Open the DMG and drag **DICOM Test Tool** onto the **Applications** folder (“Programme”).
3. Eject the disk image and start the app from Applications or Spotlight.

> [!IMPORTANT]
> **First launch:** macOS blocks the app because it is not notarised by Apple. To allow it once:
> 1. Close the message with **Done**.
> 2. Open **System Settings › Privacy & Security**.
> 3. Scroll down to *“DICOM Test Tool” was blocked* and click **Open Anyway**, then confirm.
>
> After that the app starts normally, including after in-app updates.

**Requirements:** macOS 14 Sonoma or later, Apple Silicon or Intel.

## Updates

The app checks for new versions once a day. When one is available, a window shows what's new, with an **Install and Restart** button. You can also check manually under *Über › Updates*, or from the menu bar icon. You can choose between **stable** releases and **pre-releases**.

## Privacy

- **No telemetry, no analytics, no ads, no account.** The app sends nothing to the developer.
- **Network connections** go only to the DICOM nodes you configure, and to GitHub (`api.github.com`, `github.com`) for the update check. GitHub sees your IP address for these requests; [GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement) applies. You can turn off the automatic update check.
- **Local storage only:** settings live in macOS user defaults, logs in `~/Library/Application Support/DICOM Test Tool` (kept 30 days), and received DICOM files only in the folder you choose.
- **Patient data:** DICOM objects, logs and the protocol can contain patient data. Handle them according to your organisation's policies, and **remove patient data before sharing logs or opening an issue**.

## Intended use & legal notes

- **Intended use:** setting up, testing and troubleshooting DICOM network connections, by IT staff, PACS administrators and biomedical engineers.
- **Not a medical device, not for diagnostic use** – see the warning above.
- **No certification:** this software is not certified or validated by NEMA or any other body, and makes no claim of full DICOM conformance. No DICOM Conformance Statement is provided.
- **Trademarks:** DICOM® is the registered trademark of the National Electrical Manufacturers Association (NEMA) for its standards publications relating to digital communications of medical information. It is used here only descriptively; this project is not affiliated with or endorsed by NEMA. macOS is a trademark of Apple Inc.
- **Private project:** a private, non-commercial open-source project, provided under the MIT License **without any warranty**.

## Known limitations

- No DICOM Print, no C-GET, no TLS.
- Viewer: JPEG Lossless, JPEG-LS and RLE are not decoded (tags are still shown).
- Deflated and Explicit VR Big Endian files cannot be read (receiving and forwarding them works).

## Bugs and feature requests

Please open an [**issue**](../../issues). An exported protocol (*Protokoll › Exportieren …*) helps most – **please remove patient data first**.

---

## For developers

<details>
<summary><b>Build from source</b></summary>

Requires Xcode 15 or later.

```bash
./build-app.sh
```

Output in `dist/`: `DICOM Test Tool.app`, `DICOM-Test-Tool.dmg` (drag & drop installer), `DICOM-Test-Tool.zip` plus `.sha256` (used by the updater) and the command-line tool `dicomcli`.
On the first build, macOS may ask whether Terminal may control Finder. This is needed to lay out the DMG window.

</details>

<details>
<summary><b>Publishing a release</b></summary>

1. Bump `VERSION` and add a `## <version>` section to `CHANGELOG.md`.
2. Run `./release.sh`. It builds the app and creates the DMG, ZIP, `.sha256` and `dist/RELEASE_NOTES.md`.
3. Create a GitHub release with tag `vX.Y.Z` and attach **`DICOM-Test-Tool.dmg`**, **`DICOM-Test-Tool.zip`** and **`DICOM-Test-Tool.zip.sha256`**. Do not rename these files.

The app queries `https://api.github.com/repos/<owner>/<repo>/releases/latest`. The default is `AppInfo.defaultRepository`.
For testing without GitHub, set `DICOMTESTTOOL_UPDATE_API=http://127.0.0.1:8765` to point it at a local mock server.

</details>

<details>
<summary><b>Command line (<code>dicomcli</code>)</b></summary>

```
dicomcli echo  <host> <port> <calledAE>
dicomcli store <host> <port> <calledAE> <file|folder>...
dicomcli find  <host> <port> <calledAE> [patientname]
dicomcli mwl   <host> <port> <calledAE> [patientname]
dicomcli move  <host> <port> <calledAE> <destinationAE> <studyUID>
dicomcli scp   <port> <aeTitle> <folder>
dicomcli testimage <folder> [count]
dicomcli dump  <file>
dicomcli png   <file> <output.png>
```

The calling AE title is set with the environment variable `DICOM_AET` (default: `DICOMCLI`).

</details>

<details>
<summary><b>Project layout</b></summary>

| Folder | Contents |
|---|---|
| `Sources/DicomCore` | DICOM implementation: PDUs, association, DIMSE, data sets, Part 10 files, image rendering |
| `Sources/DICOMTestTool` | SwiftUI app |
| `Sources/dicomcli` | Command-line tool |
| `Scripts` | Icon generator, DMG background and DMG builder |
| `docs` | Project website (GitHub Pages) |

</details>

## License

[MIT](LICENSE) © 2026 Martin Senft
