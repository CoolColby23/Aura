#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="${1:-$ROOT/Aura.app}"
EXPECTED_VERSION="${AURA_VERSION:-$(<"$ROOT/VERSION")}"
EXPECTED_BUILD="${AURA_BUILD_NUMBER:-1}"
PLIST="$APP/Contents/Info.plist"

fail() { echo "Package verification failed: $*" >&2; exit 1; }

[[ -x "$APP/Contents/MacOS/Aura" ]] || fail "executable is missing"
[[ -f "$PLIST" ]] || fail "Info.plist is missing"
[[ -f "$APP/Contents/Resources/Aura.icns" ]] || fail "application icon is missing"
[[ -f "$APP/Contents/Frameworks/Sparkle.framework/Sparkle" ]] || fail "Sparkle framework is missing"
RESOURCE_BUNDLE="$APP/Contents/Resources/Aura_Aura.bundle"
[[ -d "$RESOURCE_BUNDLE" ]] || fail "SwiftPM resource bundle is missing"
RESOURCE_SYMBOL="$(find "$RESOURCE_BUNDLE" -type f -name 'aura-symbol.svg' -print -quit)"
[[ -n "$RESOURCE_SYMBOL" ]] || fail "SwiftPM resource bundle is missing its symbol"
MENU_BAR_SYMBOL="$(find "$RESOURCE_BUNDLE" -type f -name 'aura-symbol-mono.svg' -print -quit)"
[[ -n "$MENU_BAR_SYMBOL" ]] || fail "SwiftPM resource bundle is missing its menu-bar symbol"
RESOURCE_INFO="$RESOURCE_BUNDLE/Contents/Info.plist"
[[ -f "$RESOURCE_INFO" ]] || RESOURCE_INFO="$RESOURCE_BUNDLE/Info.plist"
[[ -f "$RESOURCE_INFO" ]] || fail "SwiftPM resource bundle Info.plist is missing"
plutil -extract CFBundleIdentifier raw "$RESOURCE_INFO" >/dev/null \
  || fail "SwiftPM resource bundle Info.plist is invalid"
INTENTS_METADATA="$APP/Contents/Resources/Metadata.appintents"
[[ -d "$INTENTS_METADATA" ]] || fail "App Intents metadata is missing"
grep -R -q "SetAuraPrivateModeIntent" "$INTENTS_METADATA" || fail "Private Mode intent metadata is missing"
grep -R -q "OpenAuraDashboardIntent" "$INTENTS_METADATA" || fail "dashboard intent metadata is missing"

[[ "$(plutil -extract CFBundleIdentifier raw "$PLIST")" == "fm.aura.Aura" ]] || fail "bundle identifier is wrong"
[[ "$(plutil -extract CFBundleShortVersionString raw "$PLIST")" == "$EXPECTED_VERSION" ]] || fail "version is wrong"
[[ "$(plutil -extract CFBundleVersion raw "$PLIST")" == "$EXPECTED_BUILD" ]] || fail "build number is wrong"
[[ "$(plutil -extract LSMinimumSystemVersion raw "$PLIST")" == "15.0" ]] || fail "minimum macOS is wrong"
[[ -n "$(plutil -extract NSAppleEventsUsageDescription raw "$PLIST")" ]] || fail "Apple Events usage description is missing"
[[ -n "$(plutil -extract AURA_DISCORD_APPLICATION_ID raw "$PLIST")" ]] || fail "Discord application ID is missing"
[[ "$(plutil -extract SUFeedURL raw "$PLIST")" == "https://github.com/CoolColby23/Aura/releases/latest/download/appcast.xml" ]] || fail "update feed URL is wrong"
# Must match the key whose private half is the SPARKLE_PRIVATE_KEY release secret.
# generate_appcast silently emits an UNSIGNED feed when these disagree.
EXPECTED_ED_KEY="EBdOJMgejwIvsRqKDYymh1sKKNyr/e+W3XpeJyJ/cvE="
[[ "$(plutil -extract SUPublicEDKey raw "$PLIST")" == "$EXPECTED_ED_KEY" ]] || fail "Sparkle public key is missing or does not match the release signing key"
[[ "$(plutil -extract SUEnableAutomaticChecks raw "$PLIST")" == "true" ]] || fail "automatic update checks are not enabled"

otool -l "$APP/Contents/MacOS/Aura" | grep -q "@executable_path/../Frameworks" || fail "framework runtime search path is missing"
otool -L "$APP/Contents/MacOS/Aura" | grep -q "@rpath/Sparkle.framework" || fail "executable is not linked to Sparkle"

codesign --verify --deep --strict --verbose=2 "$APP"
ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null)"
[[ "$ENTITLEMENTS" == *"com.apple.security.automation.apple-events"* ]] || fail "Apple Events entitlement is missing"

echo "Verified $APP ($EXPECTED_VERSION build $EXPECTED_BUILD)"
