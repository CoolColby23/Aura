#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

# Keep local previews ahead of the production appcast without violating
# CFBundleVersion's documented four/two/two digit component limits.
export AURA_BUILD_NUMBER="${AURA_BUILD_NUMBER:-$(date -u +%Y.%m.%d)}"

"$ROOT/scripts/package-app.sh"
"$ROOT/scripts/verify-package.sh" "$ROOT/Aura.app"

# Review and CI can validate the same sync path without replacing the installed
# app or terminating a user's running copy. The production preview stays default.
TARGET_APP="${AURA_PREVIEW_APP_PATH:-/Applications/Aura.app}"
if [[ "$TARGET_APP" != /* || "${TARGET_APP:t}" != "Aura.app" || "$TARGET_APP" == "$ROOT/Aura.app" ]]; then
  echo "AURA_PREVIEW_APP_PATH must be an absolute path ending in Aura.app outside the package source" >&2
  exit 1
fi
if [[ "$TARGET_APP" == "/Applications/Aura.app" ]] && pgrep -x Aura >/dev/null; then
  pkill -x Aura
  for _ in {1..30}; do
    pgrep -x Aura >/dev/null || break
    sleep 0.1
  done
  if pgrep -x Aura >/dev/null; then
    echo "Aura did not quit; leaving the installed app untouched" >&2
    exit 1
  fi
fi
mkdir -p "${TARGET_APP:h}"
rm -rf "$TARGET_APP"
cp -R "$ROOT/Aura.app" "$TARGET_APP"
"$ROOT/scripts/verify-package.sh" "$TARGET_APP"

echo "Installed $TARGET_APP from $ROOT/Aura.app"
