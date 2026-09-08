#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CANONICAL="$ROOT/brand"
APP_BRAND="$ROOT/Sources/Aura/Resources/Brand"
WEB_BRAND="$ROOT/website/assets/brand"
# Vector marks the app bundle and the website both use. The app bundle carries no
# raster brand art: it draws the halo natively through `BrandMark`, so PNG exports
# are deliverables that live under brand/Exports rather than shipped resources.
SHARED_FILES=(
  app-icon.svg
  aura-logo-dark.svg
  aura-logo-light.svg
  aura-symbol-mono.svg
  aura-symbol.svg
)

mkdir -p "$APP_BRAND" "$WEB_BRAND" "$CANONICAL/AppIcon.iconset" "$CANONICAL/Exports"

for file in $SHARED_FILES; do
  cp "$CANONICAL/$file" "$APP_BRAND/$file"
  cp "$CANONICAL/$file" "$WEB_BRAND/$file"
done

# The Open Graph card is web-only, and social scrapers cannot render SVG, so it
# ships as a JPEG at the exact 1200x630 the meta tags declare.
sips -s format jpeg -s formatOptions 90 "$CANONICAL/og-card.svg" --out "$WEB_BRAND/og-card.jpg" >/dev/null

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Rasterize once at 1024 and resample down, so every derived size comes from the
# same render rather than from independently rasterized SVGs.
render() {
  local name="$1"
  sips -s format png "$CANONICAL/$name.svg" --out "$TEMP_DIR/$name.png" >/dev/null
  sips --resampleWidth 1024 "$TEMP_DIR/$name.png" --out "$TEMP_DIR/$name.png" >/dev/null
}

iconutil -c iconset "$CANONICAL/Aura.icns" -o "$TEMP_DIR/Aura.iconset"
MASTER_ICON="$TEMP_DIR/Aura.iconset/icon_512x512@2x.png"

for spec in \
  icon_16x16.png:16 \
  icon_16x16@2x.png:32 \
  icon_32x32.png:32 \
  icon_32x32@2x.png:64 \
  icon_128x128.png:128 \
  icon_128x128@2x.png:256 \
  icon_256x256.png:256 \
  icon_256x256@2x.png:512 \
  icon_512x512.png:512 \
  icon_512x512@2x.png:1024
do
  name="${spec%%:*}"
  size="${spec##*:}"
  sips --resampleHeightWidth "$size" "$size" "$MASTER_ICON" --out "$CANONICAL/AppIcon.iconset/$name" >/dev/null
done

# Raster deliverables: the PNG forms of every mark, for README embeds, press,
# app-store listings, and anywhere SVG is not accepted.
cp "$MASTER_ICON" "$CANONICAL/Exports/app-icon-1024.png"
for name in aura-logo-dark aura-logo-light aura-symbol-mono aura-symbol touch-icon; do
  render "$name"
  if [[ "$name" == aura-logo-* ]]; then
    # The lockup is 244x80, so width alone fixes the height.
    cp "$TEMP_DIR/$name.png" "$CANONICAL/Exports/$name.png"
  else
    sips --resampleHeightWidth 1024 1024 "$TEMP_DIR/$name.png" --out "$CANONICAL/Exports/$name.png" >/dev/null
  fi
done

# Browsers still need raster icons: Safari asks for a 180-point touch icon, and
# every non-SVG favicon consumer falls back to the PNGs declared alongside it.
sips --resampleHeightWidth 180 180 "$CANONICAL/Exports/touch-icon.png" --out "$WEB_BRAND/apple-touch-icon.png" >/dev/null
sips --resampleHeightWidth 512 512 "$CANONICAL/Exports/touch-icon.png" --out "$WEB_BRAND/favicon-512.png" >/dev/null
sips --resampleHeightWidth 32 32 "$CANONICAL/Exports/touch-icon.png" --out "$WEB_BRAND/favicon-32.png" >/dev/null
# A raster lockup at 2x the 244x80 the site declares, for feed readers and mail
# clients that strip SVG.
sips --resampleWidth 488 "$CANONICAL/Exports/aura-logo-dark.png" --out "$WEB_BRAND/aura-logo-dark.png" >/dev/null

echo "Synced app, website, and raster brand deliverables from brand/."
