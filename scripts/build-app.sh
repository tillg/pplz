#!/bin/sh
# Builds the cardXchange apps from the Xcode project in App/ (generated with XcodeGen).
#   scripts/build-app.sh mac            build the Mac app and install it in /Applications
#   scripts/build-app.sh iphone <name>  build for iPhone / iPad and install on the connected, unlocked device
#   scripts/build-app.sh simulator      build for the iOS simulator
#   scripts/build-app.sh all            the Mac app and every attached iPhone / iPad, with one build number and date
set -eu
SCRIPT="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/../App"

[ -f Local.xcconfig ] || { echo "Copy App/Local.xcconfig.example to App/Local.xcconfig and enter your team ID."; exit 1; }
xcodegen generate >/dev/null
DERIVED="../.build/xc"
# the build number is the commit count, the build date the local time (issue #12); all targets get the same values.
# `all` sets CX_BUILD and CX_BUILT, so that every platform gets the same values (issue #17).
BUILD="${CX_BUILD:-$(git rev-list --count HEAD)}"
BUILT="${CX_BUILT:-$(date '+%Y-%m-%d %H:%M')}"

case "${1:-mac}" in
all)
    export CX_BUILD="$BUILD" CX_BUILT="$BUILT"
    LIST="$(mktemp)"
    xcrun devicectl list devices --json-output "$LIST" >/dev/null
    # attached = a real device with a transport (cable or network)
    DEVICES="$(python3 -I -c 'import json,sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    if d["hardwareProperties"].get("reality") == "physical" and d["connectionProperties"].get("transportType"):
        print(d["deviceProperties"]["name"])' "$LIST")"
    rm -f "$LIST"
    echo "Build $BUILD, $BUILT"
    "$SCRIPT" mac
    echo "$DEVICES" | while IFS= read -r DEVICE; do
        [ -n "$DEVICE" ] || continue
        echo "== $DEVICE"
        "$SCRIPT" iphone "$DEVICE"
    done
    ;;
mac)
    # automatic signing: the iCloud entitlement needs a provisioning profile
    xcodebuild -project cardxchange.xcodeproj -scheme cardxchangeMac -configuration Release -derivedDataPath "$DERIVED" \
        -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD" CX_BUILD_DATE="$BUILT" build | grep -E "error:|BUILD"
    osascript -e 'tell application id "me.cardxchange.app" to quit' 2>/dev/null || true
    # move, don't copy: two registered copies would compete for cx:// links
    rm -rf /Applications/cardXchange.app
    mv "$DERIVED/Build/Products/Release/cardXchange.app" /Applications/cardXchange.app
    echo "Installed /Applications/cardXchange.app"
    ;;
iphone)
    DEVICE="${2:?device name, see: xcrun devicectl list devices}"
    # build for this very device, so that Xcode registers it and puts it into the provisioning profile
    xcodebuild -project cardxchange.xcodeproj -scheme cardxchangeiOS -configuration Debug -destination "platform=iOS,name=$DEVICE" \
        -derivedDataPath "$DERIVED" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
        CURRENT_PROJECT_VERSION="$BUILD" CX_BUILD_DATE="$BUILT" build | grep -E "error:|BUILD" | tee "$DERIVED/last-build.txt"
    # never install a stale build after a failed one
    grep -q "BUILD SUCCEEDED" "$DERIVED/last-build.txt" || exit 1
    xcrun devicectl device install app --device "$DEVICE" \
        "$DERIVED/Build/Products/Debug-iphoneos/cardXchange.app" | tail -2
    ;;
simulator)
    xcodebuild -project cardxchange.xcodeproj -scheme cardxchangeiOS -configuration Debug -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$DERIVED" CURRENT_PROJECT_VERSION="$BUILD" CX_BUILD_DATE="$BUILT" build | grep -E "error:|BUILD"
    echo "Built $DERIVED/Build/Products/Debug-iphonesimulator/cardXchange.app"
    ;;
*)
    echo "Usage: scripts/build-app.sh mac | iphone <device name> | simulator | all"; exit 1
    ;;
esac
