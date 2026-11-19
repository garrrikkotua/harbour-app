#!/bin/bash
# Writes build/release/appcast.xml for the Sparkle updater from the signed ZIP.
# The appcast is uploaded with each GitHub release; the app reads it from
# releases/latest/download/appcast.xml, so publishing a release is the update.
#
# The EdDSA private key comes from SPARKLE_PRIVATE_KEY (CI secret, exported
# with `generate_keys -x`) or, when unset, from the login keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${VERSION:?Set VERSION to x.y.z}"
APP='build/Harbour Control.app'
OUT='build/release'
ZIP="$OUT/Harbour-Control-$VERSION.zip"
REPO="${GITHUB_REPOSITORY:-garrrikkotua/harbour-app}"
[[ -f "$ZIP" ]] || { echo "Missing $ZIP" >&2; exit 1; }

SIGN_UPDATE="$(find .build/artifacts -path '*Sparkle*/bin/sign_update' -type f | head -n 1)"
[[ -x "$SIGN_UPDATE" ]] || { echo 'sign_update not found; run swift package resolve' >&2; exit 1; }

BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
SHORT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
[[ "$SHORT" == "$VERSION" ]] || { echo "App is $SHORT, expected $VERSION" >&2; exit 1; }

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  ATTRS="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$ZIP")"
else
  ATTRS="$("$SIGN_UPDATE" "$ZIP")"
fi
[[ "$ATTRS" == *'sparkle:edSignature="'* && "$ATTRS" == *'length="'* ]] || { echo 'sign_update failed' >&2; exit 1; }

URL="https://github.com/$REPO/releases/download/v$VERSION/Harbour-Control-$VERSION.zip"
NOTES="https://github.com/$REPO/releases/tag/v$VERSION"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Harbour Control</title>
    <link>https://github.com/$REPO</link>
    <item>
      <title>Harbour Control $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <link>$NOTES</link>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$NOTES</sparkle:fullReleaseNotesLink>
      <description><![CDATA[<p>See the <a href="$NOTES">release notes</a> for what changed.</p>]]></description>
      <enclosure url="$URL" type="application/octet-stream" $ATTRS />
    </item>
  </channel>
</rss>
XML
echo "Appcast: $OUT/appcast.xml (build $BUILD)"
