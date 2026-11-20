#!/bin/sh
# Builds the cardXchange apps from the Xcode project in App/ (generated with XcodeGen).
#   scripts/build-app.sh mac            build the Mac app and install it in /Applications
#   scripts/build-app.sh iphone <name>  build for iPhone / iPad and install on the connected, unlocked device
#   scripts/build-app.sh simulator      build for the iOS simulator
set -eu
cd "$(dirname "$0")/../App"

[ -f Local.xcconfig ] || { echo "Copy App/Local.xcconfig.example to App/Local.xcconfig and enter your team ID."; exit 1; }
xcodegen generate >/dev/null
DERIVED="../.build/xc"

case "${1:-mac}" in
mac)
    # automatic signing: the iCloud entitlement needs a provisioning profile
    xcodebuild -project cardxchange.xcodeproj -scheme cardxchangeMac -configuration Release -derivedDataPath "$DERIVED" \
        -allowProvisioningUpdates build | grep -E "error:|BUILD"
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
        -derivedDataPath "$DERIVED" -allowProvisioningUpdates -allowProvisioningDeviceRegistration build | grep -E "error:|BUILD" | tee "$DERIVED/last-build.txt"
    # never install a stale build after a failed one
    grep -q "BUILD SUCCEEDED" "$DERIVED/last-build.txt" || exit 1
    xcrun devicectl device install app --device "$DEVICE" \
        "$DERIVED/Build/Products/Debug-iphoneos/cardXchange.app" | tail -2
    ;;
simulator)
    xcodebuild -project cardxchange.xcodeproj -scheme cardxchangeiOS -configuration Debug -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$DERIVED" build | grep -E "error:|BUILD"
    echo "Built $DERIVED/Build/Products/Debug-iphonesimulator/cardXchange.app"
    ;;
*)
    echo "Usage: scripts/build-app.sh mac | iphone <device name> | simulator"; exit 1
    ;;
esac
