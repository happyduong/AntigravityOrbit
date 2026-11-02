#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Antigravity Orbit.app"
APP_BUNDLE="$BUILD_DIR/$APP_NAME"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE_NAME="AntigravityOrbit"

echo "=== Building Antigravity Orbit for macOS ==="

# 1. Ensure custom icon is generated
if [ ! -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    echo "Generating custom logo..."
    "$PROJECT_DIR/create_app_icon.sh"
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "2. Compiling Swift sources (arm64)..."
swiftc -O \
    -target arm64-apple-macos12.0 \
    -parse-as-library \
    "$PROJECT_DIR"/Sources/*.swift \
    -o "$MACOS_DIR/$EXECUTABLE_NAME"

echo "3. Copying Info.plist and custom AppIcon..."
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
if [ -f "$PROJECT_DIR/Resources/AppIcon1024.png" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon1024.png" "$RESOURCES_DIR/AppIcon1024.png"
fi

chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

echo "4. Code-signing app bundle (ad-hoc)..."
codesign -s - --force --deep "$APP_BUNDLE"

echo "✔ Build complete: $APP_BUNDLE"

if [ "$1" = "install" ]; then
    echo "5. Installing to /Applications/$APP_NAME..."
    # Close any currently running instance
    pkill -f "AntigravityOrbit" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME"
    cp -R "$APP_BUNDLE" "/Applications/"
    echo "✔ Successfully installed to /Applications/$APP_NAME"

    # Unload and clean LaunchAgent to prevent duplicate instances
    if [ -f "$HOME/Library/LaunchAgents/com.antigravity.orbit.plist" ]; then
        launchctl unload "$HOME/Library/LaunchAgents/com.antigravity.orbit.plist" 2>/dev/null || true
        rm -f "$HOME/Library/LaunchAgents/com.antigravity.orbit.plist"
    fi

    # Start the app directly as a standard macOS application
    sleep 0.8
    open "/Applications/$APP_NAME"
    echo "✔ Started /Applications/$APP_NAME"
elif [ "$1" = "package" ] || [ "$1" = "dmg" ]; then
    "$PROJECT_DIR/package_installer.sh"
fi
