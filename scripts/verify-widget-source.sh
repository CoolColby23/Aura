#!/bin/zsh
set -euo pipefail

# Fast source check; the package job separately builds and verifies the real
# extension product, embedded signature, sandbox and shared app group.
ROOT="${0:A:h:h}"

swiftc -typecheck -parse-as-library \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -target "$(uname -m)-apple-macos15.0" \
  "$ROOT/WidgetExtension/AuraWidget.swift"

echo "Type-checked the widget extension source."
