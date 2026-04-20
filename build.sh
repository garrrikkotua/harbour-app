#!/bin/bash
# Build Harbour.app bundle containing both the GUI and the privileged daemon.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
APP_DIR="build/Harbour.app"
BIN_DIR=".build/${CONFIG}"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG" --product Harbour
swift build -c "$CONFIG" --product harbour-daemon

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/Harbour"          "$APP_DIR/Contents/MacOS/Harbour"
cp "$BIN_DIR/harbour-daemon"   "$APP_DIR/Contents/Resources/harbour-daemon"
cp Resources/Info.plist        "$APP_DIR/Contents/Info.plist"

chmod +x "$APP_DIR/Contents/MacOS/Harbour"
chmod +x "$APP_DIR/Contents/Resources/harbour-daemon"

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo
echo "Built: $APP_DIR"
echo "Run:   open $APP_DIR"
