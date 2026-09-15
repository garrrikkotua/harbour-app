#!/bin/bash
# Build an installable universal app; use UNIVERSAL=0 for local iteration.
set -euo pipefail
cd "$(dirname "$0")"
CONFIG="${CONFIG:-release}"
UNIVERSAL="${UNIVERSAL:-1}"
VERSION="${VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
APP_DIR="build/Harbour Control.app"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'VERSION must be x.y.z' >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo 'BUILD_NUMBER must be numeric' >&2; exit 1; }
BUILD_FLAGS=(-c "$CONFIG")
if [[ "$UNIVERSAL" == 1 ]]; then BUILD_FLAGS+=(--arch arm64 --arch x86_64); fi
swift build "${BUILD_FLAGS[@]}"
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/Harbour" "$APP_DIR/Contents/MacOS/Harbour"
cp "$BIN_DIR/harbour-daemon" "$APP_DIR/Contents/Resources/harbour-daemon"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
SIGN_FLAGS=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != - ]]; then SIGN_FLAGS+=(--options runtime --timestamp); fi
# Sign nested code first, then seal the bundle. Never ignore signing failures.
codesign "${SIGN_FLAGS[@]}" "$APP_DIR/Contents/Resources/harbour-daemon"
codesign "${SIGN_FLAGS[@]}" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
if [[ "$UNIVERSAL" == 1 ]]; then
  lipo "$APP_DIR/Contents/MacOS/Harbour" -verify_arch arm64 x86_64
  lipo "$APP_DIR/Contents/Resources/harbour-daemon" -verify_arch arm64 x86_64
fi
echo "Built: $APP_DIR ($VERSION, build $BUILD_NUMBER)"
