#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

# Keep local previews ahead of the production appcast without violating
# CFBundleVersion's documented four/two/two digit component limits.
export AURA_BUILD_NUMBER="${AURA_BUILD_NUMBER:-$(date -u +%Y.%m.%d)}"

"$ROOT/scripts/package-app.sh"
"$ROOT/scripts/verify-package.sh" "$ROOT/Aura.app"

TARGET_APP="/Applications/Aura.app"
if pgrep -x Aura >/dev/null; then
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
rm -rf "$TARGET_APP"
cp -R "$ROOT/Aura.app" "$TARGET_APP"
"$ROOT/scripts/verify-package.sh" "$TARGET_APP"

echo "Installed $TARGET_APP from $ROOT/Aura.app"
