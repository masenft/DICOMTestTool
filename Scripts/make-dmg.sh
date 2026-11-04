#!/bin/zsh
# Packs the app into a drag-and-drop DMG: app icon on the left, Applications folder on the right,
# with a background image. Usage: Scripts/make-dmg.sh <path/to/App.app> <out.dmg> <version>
set -euo pipefail
APP_PATH="$1"
OUT="$2"
VERSION="$3"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="$(basename "$APP_PATH")"
VOL="DICOM Test Tool $VERSION"
WORK="${TMPDIR:-/tmp}/DICOMTestTool-dmg"

rm -rf "$WORK"; mkdir -p "$WORK/src/.background"
ditto "$APP_PATH" "$WORK/src/$APP_NAME"
ln -s /Applications "$WORK/src/Programme"
cp "$ROOT/Resources/dmg-background.tiff" "$WORK/src/.background/background.tiff"

# Detach a leftover volume of the same name from an earlier, aborted run.
[[ -d "/Volumes/$VOL" ]] && hdiutil detach "/Volumes/$VOL" -force -quiet || true

hdiutil create -quiet -srcfolder "$WORK/src" -volname "$VOL" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
DEV="$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" | awk '/Apple_HFS/ {print $1}')"
sleep 1

# Window layout via Finder. Needs the automation permission for Finder; without it the DMG
# still works, only without arranged icons and background.
if ! osascript <<OSA
tell application "Finder"
    tell disk "$VOL"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 548}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "$APP_NAME" of container window to {170, 200}
        set position of item "Programme" of container window to {490, 200}
        update without registering applications
        delay 1
        close
    end tell
end tell
OSA
then
    echo "Hinweis: Finder-Layout konnte nicht gesetzt werden (Automationsrecht für Finder fehlt?)." >&2
fi

chmod -Rf go-w "/Volumes/$VOL" || true
sync
hdiutil detach "$DEV" -quiet || hdiutil detach "$DEV" -force -quiet
rm -f "$OUT"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT"
rm -rf "$WORK"
echo "DMG: $OUT"
