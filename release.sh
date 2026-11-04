#!/bin/zsh
# Builds a release and prints the command to publish it on GitHub.
# Release notes are taken from the matching "## <version>" section in CHANGELOG.md.
set -euo pipefail
cd "$(dirname "$0")"
VERSION="$(tr -d '[:space:]' < VERSION)"

./build-app.sh
awk -v v="## $VERSION" '$0==v{f=1;next} /^## /{f=0} f' CHANGELOG.md > dist/RELEASE_NOTES.md
if [[ ! -s dist/RELEASE_NOTES.md ]]; then
  echo "Fehler: Kein Abschnitt '## $VERSION' in CHANGELOG.md" >&2
  exit 1
fi

echo
echo "Release v$VERSION vorbereitet in dist/:"
ls -1 dist/DICOM-Test-Tool.zip dist/DICOM-Test-Tool.zip.sha256 dist/dicomcli dist/RELEASE_NOTES.md
echo
echo "Veröffentlichen (GitHub CLI):"
echo "  git tag v$VERSION && git push origin v$VERSION"
echo "  gh release create v$VERSION dist/DICOM-Test-Tool.zip dist/DICOM-Test-Tool.zip.sha256 dist/dicomcli --title \"DICOM Test Tool $VERSION\" --notes-file dist/RELEASE_NOTES.md"
echo "Oder im Browser unter github.com/<owner>/<repo>/releases/new dieselben Dateien hochladen."
