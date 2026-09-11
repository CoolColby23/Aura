# Aura design tokens

These are the canonical values. They are mirrored in code by `BrandColors` /
`BrandSpacing` / `BrandRadius` / `BrandMetrics` / `BrandTypography` in
`Sources/Aura/Brand.swift` (macOS), by `CompanionBrand` / `CompanionSpacing` /
`CompanionRadius` / `CompanionMetrics` in `iOS/CompanionTheme.swift`, and by
`WidgetBrand` in `WidgetExtension/AuraWidget.swift`, which cannot import either
app module. Change them here first, then in all three.

## Gradient

The Aura sweep, in order. Used for the halo mark and live playback state only.

- `gradient-0` Peach: `#FFC49B` at 0%
- `gradient-1` Blush: `#FF9AA8` at 34%
- `gradient-2` Lilac: `#A78BFA` at 70%
- `gradient-3` Indigo: `#5B5BF5` at 100%

## Color

Brand

- `color-indigo`: `#5B5BF5` — primary action, filled control, selection
- `color-indigo-text`: `#4B45E0` — indigo as text on light surfaces
- `color-lilac`: `#A78BFA` — secondary accent, indigo's dark-mode text partner
- `color-blush`: `#FF9AA8` — live / now-playing
- `color-peach`: `#FFC49B` — gradient entry only

Neutral

- `color-ink`: `#121219` — light primary text
- `color-graphite`: `#55546B` — light secondary text
- `color-haze`: `#F7F6FB` — light canvas
- `color-veil`: `#FFFFFF` — light elevated surface
- `color-dusk`: `#0F0F17` — dark canvas
- `color-onyx`: `#17171F` — dark elevated surface
- `color-vapor`: `#A9A7BC` — dark secondary text

Status — scheme-specific so body text clears AA on its own canvas

- `color-success`: `#0F7A43` light / `#3FD483` dark
- `color-warning`: `#8A5300` light / `#F0A93B` dark
- `color-error`: `#B3242E` light / `#FF7A85` dark
- `color-neutral`: `#5A5970` light / `#A9A7BC` dark

Hairline — used only where a material step is not possible

- `color-hairline`: `rgba(0,0,0,0.06)` light / `rgba(255,255,255,0.08)` dark

## Spacing

- `space-xs`: 6
- `space-sm`: 10
- `space-md`: 16
- `space-lg`: 24
- `space-xl`: 32
- `space-2xl`: 44
- `space-3xl`: 60

## Radius

All rounding is continuous (squircle), never circular — and circular is the default for
`RoundedRectangle`, `.rect(cornerRadius:)`, and `border-radius`, so continuous has to be
asked for at every call site. Nothing card-sized or larger is squarer than `radius-sm`.

- `radius-xxs`: 6 — key caps, appearance miniatures
- `radius-xs`: 8 — chips, selection pills, artwork thumbnails, inline previews
- `radius-sm`: 12
- `radius-md`: 18
- `radius-lg`: 26
- `radius-xl`: 34
- `radius-2xl`: 44
- `radius-tile`: 28% of the tile's own edge — the tinted square behind a symbol, so
  tiles of different sizes read as one shape

Album art in the iPhone app's Last.fm views is the one deliberate exception at 3, which
matches Last.fm's own near-square grid. Artist art is a true circle, never a rounded
rectangle at half its frame.

## Component

The scales above answer "how far apart". These answer "how big is this particular
thing" for the components that repeat on every screen. They exist because those
measurements used to be literals at each call site, and the call sites drifted:
four status-dot diameters, five capsule paddings, and seven card paddings, all
describing the same component.

- `status-dot`: 7 — the filled dot in front of a connection status label
- `capsule-padding`: 9 horizontal / 5 vertical — the interior of a tinted status
  or tag capsule
- `tile-large`: 36 — the symbol tile on a card in a grid
- `tile-medium`: 32 macOS / 30 iOS — the symbol tile on a list row or command result
- `tile-small`: 28 — the symbol tile in the menu-bar panel
- `card-padding`: 16 — a card's interior
- `card-padding-compact`: 12 — a card in the menu-bar or sidebar column
- `card-padding-spacious`: 24 — a panel-scale surface, such as an onboarding step
- `title-detail`: 3 — between a heading and the caption directly beneath it
- `card-content`: 12 — between the stacked blocks inside a card
- `grid`: 14 — grid gutters, and the gap between sibling cards
- `screen-padding`: 32 — the outer padding of a scrolling detail screen
- `content-width`: 1040 — the measure each macOS detail screen centers content in
- `row-trailing-column`: 124 — the trailing status-and-timestamp column of a list row

## Type

SF Pro Rounded for chrome and headlines, SF Pro Text for long-form body, SF Mono for
technical values.

- `type-hero`: 40 / bold / rounded
- `type-title`: 24 / semibold / rounded
- `type-heading`: 18 / semibold / rounded
- `type-body`: 15 / regular / rounded
- `type-caption`: 12 / medium / rounded
- `type-mono`: 12 / regular / monospaced

## Elevation

Elevation is a tinted glow, never a black drop shadow.

- `elevation-low`: Indigo at 10%, radius 12, y-offset 4
- `elevation-high`: Indigo at 14%, radius 28, y-offset 10

## Motion

- `motion-sweep`: 12s linear, infinite — the halo gradient sweep, only while playing
- `motion-transition`: 0.28s ease-out — standard state change
- All motion freezes in place under Reduce Motion; it is never simply hidden.
