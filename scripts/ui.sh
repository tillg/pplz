#!/bin/sh
# Clicks through the iOS app in a simulator and saves screenshots and accessibility trees to tmp/ui/.
#   scripts/ui.sh "<app arguments, separated by |>" "<steps, separated by ;>" [simulator name]
#   scripts/ui.sh "-select|Anna Example" "tap:Log Event;screenshot:sheet;tree:sheet"
# Steps are described in App/UITests/ScriptRunnerTests.swift.
set -eu
cd "$(dirname "$0")/../App"
xcodegen generate >/dev/null
OUT="../tmp/ui"; RESULT="../tmp/ui-result.xcresult"
rm -rf "$OUT" "$RESULT"; mkdir -p "$OUT"
status=0
TEST_RUNNER_PPLZ_APP_ARGS="-noSync|YES|${1:-}" TEST_RUNNER_PPLZ_UI_SCRIPT="${2:-screenshot:start}" \
    xcodebuild test -project pplz.xcodeproj -scheme pplziOS -destination "platform=iOS Simulator,name=${3:-pplz iPhone}" \
    -derivedDataPath ../.build/xc -resultBundlePath "$RESULT" 2>&1 | grep -E "error:|XCTAssert|Nothing on screen|TEST (SUCCEEDED|FAILED)" || status=$?
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$OUT" >/dev/null
# give the exported files the names used in the script
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
for test in json.load(open(os.path.join(out, "manifest.json"))):
    for a in test.get("attachments", []):
        name = a.get("suggestedHumanReadableName", a["exportedFileName"]).split("_0_")[0]
        ext = os.path.splitext(a["exportedFileName"])[1]
        os.rename(os.path.join(out, a["exportedFileName"]), os.path.join(out, name + ext))
PY
ls "$OUT"
