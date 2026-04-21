#!/bin/bash
# Build Harbour.app bundle containing both the GUI and the privileged daemon.
# Produces a universal binary (arm64 + x86_64) that runs on any Mac from 2013 on.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
APP_DIR="build/Harbour Control.app"
# Skip universal mode for faster local iteration: UNIVERSAL=0 ./build.sh
UNIVERSAL="${UNIVERSAL:-1}"

if [ "$UNIVERSAL" = "1" ]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
  # SPM capitalises the config name under apple/Products/ (Release, Debug).
  CONFIG_CAPITALIZED="$(tr '[:lower:]' '[:upper:]' <<< "${CONFIG:0:1}")${CONFIG:1}"
  BIN_DIR=".build/apple/Products/${CONFIG_CAPITALIZED}"
else
  ARCH_FLAGS=()
  BIN_DIR=".build/${CONFIG}"
fi

echo "==> swift build ($CONFIG, arches: ${ARCH_FLAGS[*]:-host})"
swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --product Harbour
swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --product harbour-daemon

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/Harbour"          "$APP_DIR/Contents/MacOS/Harbour"
cp "$BIN_DIR/harbour-daemon"   "$APP_DIR/Contents/Resources/harbour-daemon"
cp Resources/Info.plist        "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns      "$APP_DIR/Contents/Resources/AppIcon.icns"

chmod +x "$APP_DIR/Contents/MacOS/Harbour"
chmod +x "$APP_DIR/Contents/Resources/harbour-daemon"

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo
echo "Built: $APP_DIR"
echo "Run:   open $APP_DIR"
