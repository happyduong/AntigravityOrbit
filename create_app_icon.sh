#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCES_DIR="$SCRIPT_DIR/Resources"
ICONSET_DIR="$RESOURCES_DIR/AppIcon.iconset"
ICNS_FILE="$RESOURCES_DIR/AppIcon.icns"
PNG_1024="$RESOURCES_DIR/AppIcon1024.png"

echo "=== Designing and generating custom logo for Antigravity Orbit ==="

mkdir -p "$RESOURCES_DIR" "$ICONSET_DIR"

# 1. Compile and run Swift icon generator to create 1024x1024 master PNG
swift "$RESOURCES_DIR/generate_icon.swift" "$PNG_1024"

# 2. Generate all standard macOS icon resolutions using sips
echo "Generating iconset resolutions..."
sips -z 16 16     "$PNG_1024" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
sips -z 32 32     "$PNG_1024" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
sips -z 32 32     "$PNG_1024" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
sips -z 64 64     "$PNG_1024" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
sips -z 128 128   "$PNG_1024" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
sips -z 256 256   "$PNG_1024" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
sips -z 256 256   "$PNG_1024" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
sips -z 512 512   "$PNG_1024" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
sips -z 512 512   "$PNG_1024" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
sips -z 1024 1024 "$PNG_1024" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null

# 3. Convert iconset to .icns using macOS iconutil
echo "Packing into AppIcon.icns..."
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"

rm -rf "$ICONSET_DIR"
echo "✔ Custom AppIcon.icns generated successfully at: $ICNS_FILE"
