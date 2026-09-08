# Aura Brand Guide

**Tagline:** Now playing, everywhere.

Aura is the soft glow around the music you are already playing. The product does not
perform, interrupt, or demand attention — it makes a private thing quietly visible in the
places you have chosen. The identity is built to match that: one luminous ring, generous
space, and materials that feel lit from behind rather than printed on top.

## What changed in this rebrand

The product was previously called **PresenceFM** and was built around a hard-edged
spinning disc in electric blue and cyan. The disc was literal — "a thing is spinning,
therefore audio" — and the cool blue palette read as utility software rather than
something personal.

Aura replaces both:

- **The name** is now a quality, not a mechanism. An aura is the visible edge of
  something present, which is exactly what the app publishes.
- **The mark** is a halo, not a disc: a soft gradient ring with a small core. The glow is
  the point, so the mark has no hard outer edge in its color form.
- **The palette** moves from cool blue/cyan to a warm-to-cool sweep — peach through
  blush and lilac into indigo. It reads as light rather than ink.
- **The surfaces** are translucent and layered, using system materials and generous
  corner radii instead of flat fills and hairline boxes.

The one thing carried forward is the slow motion signature. The disc used to rotate;
now the ring's gradient sweeps. Same tempo, softer expression.

## Logo system

- The mark is a **halo**: a soft gradient ring with a small filled core at its center, and
  a blurred copy of the ring behind it supplying the glow. Nothing else.
- Use the **color halo** wherever color and blur are available — app icon, marketing,
  light or dark UI.
- Use the **mono halo** (flat ring plus flat core, no glow) for the macOS menu bar,
  favicons below 24 px, one-color printing, and anywhere a gradient would turn to mud.
- Clear space is one ring diameter's half on every side. The glow is part of the mark;
  never crop it or let another element sit inside the halo.
- Minimum sizes: 16 px for the mono halo, 24 px for the color halo, 140 px wide for the
  full lockup. Drop the tagline below 140 px, and drop the wordmark entirely below
  24 px — show the halo alone.
- Do not: fill the ring solid, remove the core, add a third ring, replace the gradient
  with a single flat color in the color form, add a drop shadow (the glow *is* the
  shadow), stretch it into an ellipse, or place the color halo on a busy photograph.

## Color

The Aura gradient is a four-stop sweep, always in this order:

| Stop | Hex | Position |
| --- | --- | --- |
| Peach | `#FFC49B` | 0% |
| Blush | `#FF9AA8` | 34% |
| Lilac | `#A78BFA` | 70% |
| Indigo | `#5B5BF5` | 100% |

**The gradient belongs to the halo and to live playback state — nowhere else.** Do not
run it across buttons, text, cards, or page backgrounds. Keeping it confined is what
lets the rest of the system stay quiet.

### Core colors

| Role | Hex | Use |
| --- | --- | --- |
| Indigo | `#5B5BF5` | Primary actions, filled controls, selection |
| Indigo Text | `#4B45E0` | Indigo used as *text* on light surfaces (6.05:1 on Haze) |
| Lilac | `#A78BFA` | Secondary accent, indigo's dark-mode text partner |
| Blush | `#FF9AA8` | Live / now-playing state |
| Peach | `#FFC49B` | Gradient entry only; not a standalone UI color |

### Neutrals

| Role | Hex | Use |
| --- | --- | --- |
| Ink | `#121219` | Light-mode primary text |
| Graphite | `#55546B` | Light-mode secondary text (6.81:1 on Haze) |
| Haze | `#F7F6FB` | Light canvas |
| Veil | `#FFFFFF` | Light elevated surface |
| Dusk | `#0F0F17` | Dark canvas |
| Onyx | `#17171F` | Dark elevated surface |
| Vapor | `#A9A7BC` | Dark-mode secondary text (8.12:1 on Dusk) |

Both neutral ramps are tinted very slightly violet so they sit under the gradient
without going grey-green next to it. Do not substitute pure `#000` or `#888`.

### Status

Status color is semantic and independent of brand color, and is specified per scheme so
that body-size text clears WCAG AA on its own canvas.

| Role | On light (Haze) | On dark (Dusk) |
| --- | --- | --- |
| Success | `#0F7A43` (5.03:1) | `#3FD483` (9.95:1) |
| Warning | `#8A5300` (5.89:1) | `#F0A93B` (9.49:1) |
| Error | `#B3242E` (6.09:1) | `#FF7A85` (7.61:1) |
| Neutral | `#5A5970` (6.30:1) | `#A9A7BC` (8.12:1) |

Always pair a status color with text or an icon. Never encode state in color alone.

## Materials and shape

This is where "modern" actually lives, more than in the palette.

- **Surfaces are materials, not fills.** Cards, popovers, and the menu-bar panel use
  system materials (`.regularMaterial` / `.thinMaterial`) over the canvas so content
  behind them contributes depth. Reserve opaque fills for surfaces that must stay
  legible over arbitrary album artwork.
- **Separation comes from light, not lines.** Prefer a soft ambient glow or a material
  step over a hairline border. Where a hairline is unavoidable, use white at 8% on dark
  and black at 6% on light.
- **Corner radii are generous and continuous.** Always use `.continuous` rounding:
  12 / 18 / 26 / 34 / 44. Nothing interactive is squarer than 12.
- **Spacing rhythm** is 6 / 10 / 16 / 24 / 32 / 44 / 60.
- **Elevation** is a blur-and-glow pair, never a hard drop shadow: tint the shadow with
  Indigo at low opacity rather than black.

## Typography

- **SF Pro Rounded** for the product name, headlines, and all interface chrome. The
  rounded face is the typographic half of "soft and tactile" and is used throughout the
  app, not just in marketing.
- **SF Pro Text** for long-form body copy and documentation, where rounded gets tiring.
- **SF Mono** for diagnostics, identifiers, and technical values only.
- Marketing hierarchy: 52/56 bold headline, 22/32 regular deck, 17/28 body, 12/16
  semibold label with 1.05 tracking for all-caps.

## Imagery and motion

Favor deep, softly lit fields with the halo as the only bright object in frame. Album
artwork may supply ambient color behind a blurred surface, but never sits behind text
without a material between them.

The motion signature is a **slow gradient sweep around the ring** — one revolution every
12 seconds, while and only while something is playing. Never sync it to tempo, never
speed it up to signal urgency, and always respect Reduce Motion by freezing the sweep in
place rather than hiding the mark.

Avoid equalizer bars, headphones, vinyl nostalgia, faux hardware, waveforms, and any
imagery resembling Apple, Discord, or Last.fm's own visual language.

## Voice

Aura is warm, direct, and transparent, and never performative about privacy. Sharing is
something you switch on deliberately, so the copy never congratulates the user for being
careful — it just tells them what is on.

Messaging pillars:

1. **Live presence:** What you play can appear where your friends are.
2. **Continuous history:** Qualified listens reach Last.fm reliably, even after brief
   interruptions.
3. **Visible control:** Sharing starts deliberately and private mode is always close.

Write short, active sentences. Say exactly what is shared and where. Prefer "Go Private"
to vague security language. Avoid "always watching," "broadcast everything," protocol
jargon, and any claim implying affiliation with Apple, Discord, or Last.fm.

## Ready-to-use copy

- Short description: "Share what's playing across your music apps on Discord and keep
  Last.fm in sync — from one private-by-default Mac app."
- Launch headline: "Now playing, everywhere."
- Launch deck: "Aura carries the track you're playing into Discord and Last.fm, with
  privacy controls always within reach."
- Social: "Now playing, everywhere. Aura connects your music apps to Discord Rich
  Presence and Last.fm."
- Onboarding welcome: "Let's give your music an aura."
- Empty state: "Nothing playing yet. Start a song in a supported music app and Aura will
  pick it up."
- Private confirmation: "You're private. Discord presence is cleared and Last.fm updates
  are paused."

## Accessibility

Every text pair in the tables above was measured, not estimated. Use Ink on Haze and Haze
on Dusk for primary text; Graphite on Haze and Vapor on Dusk for secondary. Indigo Text —
not Indigo — is the light-mode text form of the brand color.

Never place text on the gradient itself. Always provide "Aura" as accessible text
wherever the halo appears alone, and preserve the mono halo's silhouette (ring + core) as
the accessible shape at every size — it must stay identifiable without color, blur, or
motion.
