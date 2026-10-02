#!/usr/bin/env bash
# Builds GitHubBar-<version>.dmg without an Apple Developer account.
# The app is ad-hoc signed, so on first launch users must allow it once:
# System Settings → Privacy & Security → "Open Anyway".
#
# Usage: scripts/make-dmg.sh
#   VERSION=0.2.0 BUILD_NUMBER=42 scripts/make-dmg.sh   # override the version from project.yml
set -euo pipefail
# Use full Xcode when the active developer dir is only the Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

VERSION_OVERRIDES=()
[[ -n "${VERSION:-}" ]] && VERSION_OVERRIDES+=("MARKETING_VERSION=$VERSION")
[[ -n "${BUILD_NUMBER:-}" ]] && VERSION_OVERRIDES+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")

cd "$(dirname "$0")/.."
OUT=build/dmg
rm -rf "$OUT" && mkdir -p "$OUT"
xcodegen generate -q

xcodebuild build -quiet \
  -project GitHubBar.xcodeproj -scheme GitHubBar -configuration Release \
  -derivedDataPath build/dmg-derived \
  -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  ${VERSION_OVERRIDES[@]+"${VERSION_OVERRIDES[@]}"}

APP=build/dmg-derived/Build/Products/Release/GitHubBar.app
# Re-sign ad hoc with hardened runtime, inside out, as Sparkle documents for sandboxed apps.
# No --deep: it would put the app's sandbox entitlements on Sparkle's helpers and break updates.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
codesign -f -s - -o runtime "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
codesign -f -s - -o runtime --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
codesign -f -s - -o runtime "$SPARKLE/Versions/B/Autoupdate"
codesign -f -s - -o runtime "$SPARKLE/Versions/B/Updater.app"
codesign -f -s - -o runtime "$SPARKLE"
codesign -f -s - -o runtime --entitlements GitHubBar/GitHubBar.entitlements "$APP"
codesign --verify --deep --strict "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
STAGE="$OUT/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/How to open.txt" <<'TXT'
GitHubBar isn't signed with a paid Apple Developer ID, so macOS blocks it the first time.

1. Drag GitHubBar to Applications.
2. Open it. macOS will say it can't verify the app. Click "Done".
3. Open System Settings → Privacy & Security, scroll down and click "Open Anyway".
4. Open GitHubBar again and confirm. You only need to do this once.

Alternatively, run this in Terminal:
  xattr -dr com.apple.quarantine /Applications/GitHubBar.app
TXT

DMG="$OUT/GitHubBar-$VERSION.dmg"
# hdiutil occasionally writes a broken image on CI runners (v0.0.3 shipped one, so Sparkle
# couldn't extract the update). Mount every image like Sparkle does and retry if that fails.
for attempt in 1 2 3; do
  rm -f "$DMG"
  hdiutil create -quiet -volname "GitHubBar $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
  MOUNT=$(mktemp -d)
  if hdiutil attach -quiet -nobrowse -noautoopen -readonly -mountpoint "$MOUNT" "$DMG" 2>/dev/null; then
    VALID=$([[ -x "$MOUNT/GitHubBar.app/Contents/MacOS/GitHubBar" ]] && echo yes || echo no)
    hdiutil detach -quiet "$MOUNT"
    rmdir "$MOUNT"
    [[ "$VALID" == yes ]] && break
  else
    rmdir "$MOUNT"
  fi
  if [[ $attempt == 3 ]]; then
    echo "❌ Couldn't create a valid DMG" >&2
    exit 1
  fi
  echo "⚠️ Invalid DMG (attempt $attempt), retrying…" >&2
  sleep 5
done
rm -rf "$STAGE"
echo "✅ $DMG ($(du -h "$DMG" | cut -f1))"
# Let CI pick up the path.
[[ -n "${GITHUB_OUTPUT:-}" ]] && echo "dmg=$DMG" >> "$GITHUB_OUTPUT"
exit 0
