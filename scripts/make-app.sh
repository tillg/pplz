#!/bin/sh
# Builds the Mac app and wraps it into .build/pplz.app (interim, until there is an Xcode project).
# Usage: scripts/make-app.sh [--install]   (--install copies it to /Applications)
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product PplzApp
BIN="$(swift build -c release --show-bin-path)/PplzApp"
APP=".build/pplz.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PplzApp"
cp assets/pplz.icns "$APP/Contents/Resources/pplz.icns"
cp scripts/Info.plist "$APP/Contents/Info.plist"

# Sign with the Apple Development identity if there is one, otherwise ad hoc.
IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
codesign --force --sign "${IDENTITY:--}" "$APP"

if [ "${1:-}" = "--install" ]; then
    # move, don't copy: two registered copies would compete for pplz:// links
    rm -rf /Applications/pplz.app
    mv "$APP" /Applications/pplz.app
    echo "Installed /Applications/pplz.app"
else
    echo "Built $APP"
fi
