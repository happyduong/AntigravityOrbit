#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Antigravity Orbit.app"
APP_BUNDLE="$BUILD_DIR/$APP_NAME"
VERSION="1.0.0"
DMG_NAME="Antigravity-Orbit-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
ZIP_NAME="Antigravity-Orbit-${VERSION}-macOS.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"

echo "=== Packaging Antigravity Orbit Installer ==="

# 1. Build app if needed
if [ ! -d "$APP_BUNDLE" ]; then
    echo "App bundle not found, running build.sh..."
    "$PROJECT_DIR/build.sh"
fi

# 2. Prepare staging directory for DMG
DMG_STAGE="$BUILD_DIR/dmg_staging"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"

echo "1. Staging files for DMG..."
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

# Set volume icon if AppIcon.icns exists
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$DMG_STAGE/.VolumeIcon.icns"
    SetFile -c icnC "$DMG_STAGE/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$DMG_STAGE" 2>/dev/null || true
fi

# 3. Create DMG disk image
echo "2. Creating compressed DMG image..."
rm -f "$DMG_PATH"
hdiutil create \
    -volname "Antigravity Orbit" \
    -srcfolder "$DMG_STAGE" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGE"

# 4. Create ZIP archive
echo "3. Creating ZIP distribution archive..."
rm -f "$ZIP_PATH"
(cd "$BUILD_DIR" && zip -r -q -y "$ZIP_NAME" "$APP_NAME")

# 5. Display info
echo ""
echo "✔ Successfully packaged installer files:"
echo "--------------------------------------------------"
echo "📦 DMG Installer: $DMG_PATH"
ls -lh "$DMG_PATH" | awk '{print "   Size: " $5}'
echo "   SHA256: $(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
echo ""
echo "📦 ZIP Archive  : $ZIP_PATH"
ls -lh "$ZIP_PATH" | awk '{print "   Size: " $5}'
echo "   SHA256: $(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo "--------------------------------------------------"
echo "To install from DMG, double-click the .dmg file and drag 'Antigravity Orbit' to 'Applications'."
