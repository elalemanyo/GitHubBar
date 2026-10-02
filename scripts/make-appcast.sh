#!/usr/bin/env bash
# Signs a DMG with the Sparkle private key and writes appcast.xml next to it.
# The release workflow attaches appcast.xml to the GitHub release; the app reads it from
# https://github.com/<repo>/releases/latest/download/appcast.xml (pre-releases are never "latest").
#
# Usage: SPARKLE_PRIVATE_KEY=... scripts/make-appcast.sh build/dmg/GitHubBar-0.2.0.dmg
# Run scripts/make-dmg.sh first: it builds the app and fetches Sparkle's tools.
set -euo pipefail
: "${SPARKLE_PRIVATE_KEY:?Set SPARKLE_PRIVATE_KEY to the exported Sparkle private key}"
DMG="${1:?Pass the DMG path}"

cd "$(dirname "$0")/.."
REPO="${GITHUB_REPOSITORY:-elalemanyo/GitHubBar}"
BIN=build/dmg-derived/SourcePackages/artifacts/sparkle/Sparkle/bin
PLIST=build/dmg-derived/Build/Products/Release/GitHubBar.app/Contents/Info.plist

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST")
MIN_SYSTEM=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "$PLIST")

# The key goes through stdin so it never touches the disk.
SIGNATURE=$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$BIN/sign_update" --ed-key-file - -p "$DMG")
LENGTH=$(stat -f%z "$DMG")
URL="https://github.com/$REPO/releases/download/v$VERSION/$(basename "$DMG")"
DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")

APPCAST="$(dirname "$DMG")/appcast.xml"
cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>GitHubBar</title>
    <link>https://github.com/$REPO</link>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_SYSTEM</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/$REPO/releases/tag/v$VERSION</sparkle:fullReleaseNotesLink>
      <enclosure url="$URL" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$SIGNATURE"/>
    </item>
  </channel>
</rss>
XML
echo "✅ $APPCAST (GitHubBar $VERSION, build $BUILD)"
