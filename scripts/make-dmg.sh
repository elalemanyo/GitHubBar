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
# Re-sign ad hoc with hardened runtime so every nested binary has a consistent signature.
# Pass the entitlements again, otherwise re-signing drops the sandbox and network access.
codesign --force --deep --options runtime --entitlements GitHubBar/GitHubBar.entitlements --sign - "$APP"
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
hdiutil create -quiet -volname "GitHubBar $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"
echo "✅ $DMG ($(du -h "$DMG" | cut -f1))"
# Let CI pick up the path.
[[ -n "${GITHUB_OUTPUT:-}" ]] && echo "dmg=$DMG" >> "$GITHUB_OUTPUT"
exit 0
