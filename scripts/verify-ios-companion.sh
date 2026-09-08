#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${TMPDIR:-/tmp}/Aura-iOS-Verification"
ICON="$ROOT/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
SIMULATOR_ID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in reversed(list(devices.values())):
    for device in runtime:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            print(device["udid"])
            raise SystemExit
')"

if [[ -z "$SIMULATOR_ID" ]]; then
    echo "No available iPhone simulator was found for companion tests." >&2
    exit 1
fi

plutil -lint "$ROOT/iOS/Info.plist" >/dev/null
jq empty "$ROOT/iOS/Assets.xcassets/AppIcon.appiconset/Contents.json"
jq empty "$ROOT/iOS/Assets.xcassets/AccentColor.colorset/Contents.json"

dimensions="$(sips -g pixelWidth -g pixelHeight "$ICON" 2>/dev/null)"
grep -q 'pixelWidth: 1024' <<< "$dimensions"
grep -q 'pixelHeight: 1024' <<< "$dimensions"
grep -q 'aura' "$ROOT/iOS/Info.plist"
grep -q 'lastfm-auth' "$ROOT/iOS/CompanionLastFMClient.swift"
grep -q 'presence-fm.vercel.app/lastfm-callback.html' "$ROOT/iOS/CompanionLastFMClient.swift"

if grep -R -n -E '\.pink|FF2D55|magenta' "$ROOT/iOS" --include='*.swift' --include='*.json'; then
    echo "Retired pink/magenta branding remains in the iOS app."
    exit 1
fi

rm -rf "$DERIVED_DATA"
BUILD_LOG="$(mktemp -t aura-ios-build).log"
trap 'rm -f "$BUILD_LOG"' EXIT
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
if ! AURA_REQUIRE_LOCAL_CONFIG=NO xcodebuild \
    -project "$ROOT/AuraiOS.xcodeproj" \
    -scheme AuraiOS \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS="$(uname -m)" \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    AURA_REQUIRE_LOCAL_CONFIG=NO \
    test >"$BUILD_LOG" 2>&1; then
  tail -n 200 "$BUILD_LOG" >&2
  exit 1
fi
rm -f "$BUILD_LOG"
trap - EXIT

echo "iOS companion branding, callback registration, assets, and simulator tests verified."
