#!/bin/sh
# Builds the pplz apps from the Xcode project in App/ (generated with XcodeGen).
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
    xcodebuild -project pplz.xcodeproj -scheme pplzMac -configuration Release -derivedDataPath "$DERIVED" \
        -allowProvisioningUpdates build | grep -E "error:|BUILD"
    osascript -e 'tell application id "com.tillg.pplz" to quit' 2>/dev/null || true
    # move, don't copy: two registered copies would compete for pplz:// links
    rm -rf /Applications/pplz.app
    mv "$DERIVED/Build/Products/Release/pplz.app" /Applications/pplz.app
    echo "Installed /Applications/pplz.app"
    ;;
iphone)
    DEVICE="${2:?device name, see: xcrun devicectl list devices}"
    # build for this very device, so that Xcode registers it and puts it into the provisioning profile
    xcodebuild -project pplz.xcodeproj -scheme pplziOS -configuration Debug -destination "platform=iOS,name=$DEVICE" \
        -derivedDataPath "$DERIVED" -allowProvisioningUpdates -allowProvisioningDeviceRegistration build | grep -E "error:|BUILD"
    xcrun devicectl device install app --device "$DEVICE" \
        "$DERIVED/Build/Products/Debug-iphoneos/pplz.app" | tail -2
    ;;
simulator)
    xcodebuild -project pplz.xcodeproj -scheme pplziOS -configuration Debug -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$DERIVED" build | grep -E "error:|BUILD"
    echo "Built $DERIVED/Build/Products/Debug-iphonesimulator/pplz.app"
    ;;
*)
    echo "Usage: scripts/build-app.sh mac | iphone <device name> | simulator"; exit 1
    ;;
esac
