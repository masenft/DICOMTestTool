#!/bin/zsh
# Builds a joint release (macOS + Windows) and prints the command to publish it on GitHub.
# Release notes are taken from the matching "## <version>" section in CHANGELOG.md.
# Both platforms always ship in the same release: the macOS updater only accepts DICOM-Test-Tool.zip,
# the Windows updater (Velopack) reads releases.win.json – never add another .zip to a release.
set -euo pipefail
cd "$(dirname "$0")"
VERSION="$(tr -d '[:space:]' < VERSION)"

./build-app.sh
awk -v v="## $VERSION" '$0==v{f=1;next} /^## /{f=0} f' CHANGELOG.md > dist/RELEASE_NOTES.md
if [[ ! -s dist/RELEASE_NOTES.md ]]; then
  echo "Fehler: Kein Abschnitt '## $VERSION' in CHANGELOG.md" >&2
  exit 1
fi
windows/build/publish-win.sh

MAC=(dist/DICOM-Test-Tool.dmg dist/DICOM-Test-Tool.zip dist/DICOM-Test-Tool.zip.sha256 dist/dicomcli)
WIN=(dist-win/DICOM-Test-Tool-win-Setup.exe dist-win/DICOM-Test-Tool-win-Setup.exe.sha256 dist-win/DICOMTestTool-$VERSION-full.nupkg dist-win/releases.win.json dist-win/assets.win.json dist-win/RELEASES)
PRE=""; [[ "$VERSION" == *-* ]] && PRE="--prerelease"

echo
echo "Release v$VERSION vorbereitet:"
ls -1 "${MAC[@]}" "${WIN[@]}" dist/RELEASE_NOTES.md
echo
echo "Veröffentlichen (GitHub CLI):"
echo "  git tag v$VERSION && git push origin v$VERSION"
echo "  gh release create v$VERSION ${MAC[*]} ${WIN[*]} $PRE --title \"DICOM Test Tool $VERSION\" --notes-file dist/RELEASE_NOTES.md"
