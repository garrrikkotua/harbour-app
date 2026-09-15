#!/bin/bash
# Requires a Developer ID Application identity and a notarytool keychain profile.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGNING_IDENTITY:?Set the Developer ID Application signing identity}"
: "${NOTARY_PROFILE:?Set the notarytool keychain profile name}"
: "${VERSION:?Set VERSION to x.y.z}"
[[ "$SIGNING_IDENTITY" != - ]] || { echo 'Public releases must be Developer ID signed.' >&2; exit 1; }
export SIGNING_IDENTITY VERSION
UNIVERSAL=1 ./build.sh
APP='build/Harbour Control.app'
OUT="build/release"
mkdir -p "$OUT"
STAGING="$(mktemp -d "$PWD/build/dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
# Staple the app before packaging so ZIP installs work offline too.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGING/notarize.zip"
xcrun notarytool submit "$STAGING/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
rm "$STAGING/notarize.zip"
ditto "$APP" "$STAGING/Harbour Control.app"
ln -s /Applications "$STAGING/Applications"
DMG="$OUT/Harbour-Control-$VERSION.dmg"
hdiutil create -volname 'Harbour Control' -srcfolder "$STAGING" -ov -format UDZO "$DMG"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/Harbour-Control-$VERSION.zip"
cp "$DMG" "$OUT/Harbour-Control-latest.dmg"
(cd "$OUT" && shasum -a 256 "Harbour-Control-$VERSION.dmg" "Harbour-Control-$VERSION.zip" Harbour-Control-latest.dmg > SHA256SUMS.txt)
echo "Signed and notarized installers: $OUT"
