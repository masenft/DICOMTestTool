#!/bin/zsh
# Builds "DICOM Test Tool.app" (Universal: Apple Silicon + Intel) and the dicomcli tool into ./dist
set -euo pipefail
cd "$(dirname "$0")"

APP="DICOM Test Tool"
BUNDLE_ID="de.martinsenft.dicomtesttool"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
# Build outside iCloud Drive so the build folder is not synced.
BUILD_DIR="${TMPDIR:-/tmp}/DICOMTestTool-build"

swift build -c release --arch arm64 --arch x86_64 --scratch-path "$BUILD_DIR"
STAGE="$BUILD_DIR/stage"
BIN="$(swift build -c release --arch arm64 --arch x86_64 --scratch-path "$BUILD_DIR" --show-bin-path)"

# Assemble and sign outside iCloud Drive (iCloud adds extended attributes codesign rejects).
rm -rf "$STAGE"
mkdir -p "$STAGE/$APP.app/Contents/MacOS" "$STAGE/$APP.app/Contents/Resources"
cp "$BIN/DICOMTestTool" "$STAGE/$APP.app/Contents/MacOS/DICOMTestTool"
cp "$BIN/dicomcli" "$STAGE/dicomcli"
cp Resources/AppIcon.icns "$STAGE/$APP.app/Contents/Resources/AppIcon.icns"

cat > "$STAGE/$APP.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP</string>
    <key>CFBundleDisplayName</key><string>$APP</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>DICOMTestTool</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.medical</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSLocalNetworkUsageDescription</key><string>Das DICOM Test Tool verbindet sich mit DICOM-Geräten und PACS-Servern im lokalen Netzwerk.</string>
</dict>
</plist>
EOF

xattr -cr "$STAGE"
codesign --force --deep --sign - "$STAGE/$APP.app"
codesign --force --sign - "$STAGE/dicomcli"

mkdir -p dist
rm -rf "dist/$APP.app" dist/dicomcli
ditto "$STAGE/$APP.app" "dist/$APP.app"
ditto "$STAGE/dicomcli" dist/dicomcli
(cd "$STAGE" && ditto -c -k --keepParent "$APP.app" "$OLDPWD/dist/DICOM-Test-Tool.zip")
(cd dist && shasum -a 256 DICOM-Test-Tool.zip > DICOM-Test-Tool.zip.sha256)
echo "Fertig: $(pwd)/dist/$APP.app (Version $VERSION, Build $BUILD_NUMBER)"
