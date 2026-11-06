#!/bin/zsh
# Builds the Windows version on the Mac (or on Linux/CI): self-contained win-x64 + Velopack setup.
# Output: ../dist-win/  (DICOM-Test-Tool-win-Setup.exe, Velopack update packages, portable exe for tests)
set -euo pipefail
cd "$(dirname "$0")/.."
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
[[ -x "$HOME/.dotnet/dotnet" ]] && export PATH="$HOME/.dotnet:$PATH"

VERSION="$(tr -d '[:space:]' < ../VERSION)"
RID="${RID:-win-x64}"
TFM="net10.0-windows10.0.19041.0"
WORK="${TMPDIR:-/tmp}/DICOMTestTool-win-$RID"
OUT="../dist-win"

rm -rf "$WORK" "$OUT" && mkdir -p "$WORK/publish" "$WORK/portable" "$OUT"
dotnet tool restore >/dev/null
dotnet test tests/DicomTestTool.Core.Tests -c Release --nologo -v q
# Installed version: a normal folder (fastest start, no self-extraction); portable: one EXE.
dotnet publish src/DicomTestTool -c Release -f "$TFM" -r "$RID" --self-contained \
  -p:PublishSingleFile=false -o "$WORK/publish" --nologo -v q
dotnet publish src/DicomTestTool -c Release -f "$TFM" -r "$RID" --self-contained \
  -p:PublishSingleFile=true -o "$WORK/portable" --nologo -v q

# Release notes: the "## <version>" section of CHANGELOG.md
awk -v v="## $VERSION" '$0==v{f=1;next} /^## /{f=0} f' ../CHANGELOG.md > "$WORK/notes.md"
[[ -s "$WORK/notes.md" ]] || echo "Version $VERSION" > "$WORK/notes.md"

dotnet vpk "[win]" pack \
  --packId DICOMTestTool --packVersion "$VERSION" --packDir "$WORK/publish" --mainExe DICOMTestTool.exe \
  --packTitle "DICOM Test Tool für Windows" --packAuthors "Martin Senft" \
  --icon src/DicomTestTool/Assets/app.ico --releaseNotes "$WORK/notes.md" \
  --runtime "$RID" --noPortable --outputDir "$WORK/releases"

# Setup with a fixed, descriptive name; the mac updater ignores it (no .zip).
cp "$WORK/releases/DICOMTestTool-win-Setup.exe" "$OUT/DICOM-Test-Tool-win-Setup.exe"
cp "$WORK/releases/"*.nupkg "$WORK/releases/releases.win.json" "$OUT/"
[[ -f "$WORK/releases/assets.win.json" ]] && cp "$WORK/releases/assets.win.json" "$OUT/"
[[ -f "$WORK/releases/RELEASES" ]] && cp "$WORK/releases/RELEASES" "$OUT/"
# Portable exe: runs without installation (no automatic updates). Part of the release – an .exe, not a .zip.
cp "$WORK/portable/DICOMTestTool.exe" "$OUT/DICOM-Test-Tool-win-portable.exe"
cp "$WORK/notes.md" "$OUT/RELEASE_NOTES.md"
(cd "$OUT" && shasum -a 256 DICOM-Test-Tool-win-Setup.exe > DICOM-Test-Tool-win-Setup.exe.sha256 \
  && shasum -a 256 DICOM-Test-Tool-win-portable.exe > DICOM-Test-Tool-win-portable.exe.sha256)

echo
echo "Fertig: Windows-Version $VERSION in $(cd "$OUT" && pwd)"
ls -la "$OUT"
