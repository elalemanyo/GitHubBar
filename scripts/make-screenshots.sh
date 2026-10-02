#!/usr/bin/env bash
# Renders the website/README screenshots (docs/screenshots/*-light.png and *-dark.png)
# from the real app views with demo data. Nothing is read from or written to your settings.
# Usage: scripts/make-screenshots.sh
set -euo pipefail
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

cd "$(dirname "$0")/.."
OUT="$PWD/docs/screenshots"
xcodegen generate -q

# Unsigned Debug build: it runs outside the app sandbox, so it can write into docs/.
xcodebuild build -quiet \
  -project GitHubBar.xcodeproj -scheme GitHubBar -configuration Debug \
  -derivedDataPath build/preview-derived -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO

rm -rf "$OUT"
build/preview-derived/Build/Products/Debug/GitHubBar.app/Contents/MacOS/GitHubBar --preview "$OUT"
ls "$OUT" | sed 's/^/  /'
echo "✅ $OUT ($(du -sh "$OUT" | cut -f1))"
