#!/bin/zsh
set -euo pipefail

# The widget extension is not embedded by the SwiftPM package or the Xcode
# project — see Documentation/WIDGET.md for the signing prerequisites — so
# nothing else in CI compiles it. Type-check it directly to keep the source
# honest while it waits for an App ID.
ROOT="${0:A:h:h}"

swiftc -typecheck -parse-as-library \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -target "$(uname -m)-apple-macos15.0" \
  "$ROOT/WidgetExtension/AuraWidget.swift"

echo "Type-checked the widget extension source."
