#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
BIN_DIR="$SCRIPT_DIR/src-tauri/target/release"
APP_NAME="antigravity-orbit"
VERSION="1.0.0"

export PATH="$HOME/.cargo/bin:$PATH"

echo "=== Building Antigravity Orbit for Linux ==="

# 1. Check Rust & Bun/Node
if ! command -v cargo >/dev/null 2>&1; then
    echo "❌ cargo (Rust) is required. Please install via: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
fi

mkdir -p "$DIST_DIR"

if [ "$1" = "bundle" ] || [ "$1" = "package" ]; then
    echo "1. Building complete Tauri distribution bundle (AppImage, .deb, .rpm)..."
    cd "$SCRIPT_DIR"
    if command -v bun >/dev/null 2>&1; then
        bun x @tauri-apps/cli build
    else
        npx @tauri-apps/cli build
    fi
    echo "✔ Distribution bundles created in $SCRIPT_DIR/src-tauri/target/release/bundle/"
elif [ "$1" = "install" ]; then
    echo "1. Compiling release binary..."
    cd "$SCRIPT_DIR/src-tauri"
    cargo build --release

    echo "2. Installing to ~/.local/bin/..."
    mkdir -p "$HOME/.local/bin"
    cp "$BIN_DIR/$APP_NAME" "$HOME/.local/bin/$APP_NAME"
    chmod +x "$HOME/.local/bin/$APP_NAME"

    echo "3. Installing Desktop Entry to ~/.local/share/applications/..."
    mkdir -p "$HOME/.local/share/applications"
    mkdir -p "$HOME/.local/share/icons/hicolor/512x512/apps"
    cp "$SCRIPT_DIR/ui/assets/AppIcon1024.png" "$HOME/.local/share/icons/hicolor/512x512/apps/antigravity-orbit.png"

    cat <<EOF > "$HOME/.local/share/applications/antigravity-orbit.desktop"
[Desktop Entry]
Type=Application
Name=Antigravity Orbit
Comment=Google AI Quota Monitor & Smart Account Rotator
Exec=$HOME/.local/bin/$APP_NAME
Icon=antigravity-orbit
Terminal=false
Categories=Utility;Development;
StartupNotify=true
EOF

    echo "✔ Successfully installed to ~/.local/bin/$APP_NAME"
    echo "✔ Desktop shortcut created at ~/.local/share/applications/antigravity-orbit.desktop"
else
    echo "1. Compiling release binary..."
    cd "$SCRIPT_DIR/src-tauri"
    cargo build --release

    cp "$BIN_DIR/$APP_NAME" "$DIST_DIR/$APP_NAME"
    echo "✔ Binary built successfully: $DIST_DIR/$APP_NAME"

    # Create portable tarball
    TAR_NAME="Antigravity-Orbit-${VERSION}-linux.tar.gz"
    echo "2. Packaging portable tarball: $DIST_DIR/$TAR_NAME..."
    (cd "$DIST_DIR" && tar -czf "$TAR_NAME" "$APP_NAME")
    echo "✔ Tarball created: $DIST_DIR/$TAR_NAME"
fi

