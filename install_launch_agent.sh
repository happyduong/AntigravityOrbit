#!/bin/bash
set -e

APP_NAME="Antigravity Orbit"
APP_PATH="/Applications/$APP_NAME.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

# Clean any legacy LaunchAgent
cleanup_legacy() {
    if [ -f "$LAUNCH_AGENTS_DIR/com.antigravity.orbit.plist" ]; then
        launchctl unload "$LAUNCH_AGENTS_DIR/com.antigravity.orbit.plist" 2>/dev/null || true
        rm -f "$LAUNCH_AGENTS_DIR/com.antigravity.orbit.plist"
    fi
}

case "$1" in
    install)
        cleanup_legacy
        if [ -d "$APP_PATH" ]; then
            osascript -e "tell application \"System Events\" to if not (exists (login item \"$APP_NAME\")) then make login item at end with properties {name:\"$APP_NAME\", path:\"$APP_PATH\", hidden:false}"
            echo "✔ Added $APP_NAME to macOS Login Items."
            # Start app if not running
            if ! pgrep -f "AntigravityOrbit" >/dev/null; then
                open -a "$APP_PATH"
                echo "✔ Started $APP_NAME."
            fi
        else
            echo "❌ $APP_PATH not found. Please run ./build.sh install first."
            exit 1
        fi
        ;;
    uninstall)
        cleanup_legacy
        osascript -e "tell application \"System Events\" to delete (every login item whose name is \"$APP_NAME\")" 2>/dev/null || true
        echo "✔ Removed $APP_NAME from macOS Login Items."
        ;;
    status)
        EXISTS=$(osascript -e "tell application \"System Events\" to exists (login item \"$APP_NAME\")" 2>/dev/null || echo "false")
        RUNNING=$(pgrep -f "AntigravityOrbit" >/dev/null && echo "Running" || echo "Stopped")
        echo "Login Item: $EXISTS"
        echo "App Process: $RUNNING"
        ;;
    *)
        echo "Usage: $0 {install|uninstall|status}"
        exit 1
        ;;
esac
