#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
OUTPUT="${1:?Usage: build-widget.sh OUTPUT_DIRECTORY}"
DERIVED="$(mktemp -d -t aura-widget-build)"
trap 'rm -rf "$DERIVED"' EXIT
# Build an actual extension product. Signing is deliberately performed by the
# packaging step, inside-out, using the same identity as the containing app.
xcodebuild -quiet -project "$ROOT/AuraWidget.xcodeproj" -target AuraWidget \
  -configuration Release SYMROOT="$DERIVED/products" OBJROOT="$DERIVED/objects" \
  CODE_SIGNING_ALLOWED=NO MARKETING_VERSION="${AURA_VERSION:-$(<"$ROOT/VERSION")}" \
  CURRENT_PROJECT_VERSION="${AURA_BUILD_NUMBER:-1}" build
mkdir -p "$OUTPUT"
ditto "$DERIVED/products/Release/AuraWidget.appex" "$OUTPUT/AuraWidget.appex"
