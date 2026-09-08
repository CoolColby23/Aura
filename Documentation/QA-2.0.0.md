# Aura 2.0.0 Validation Record

Updated: 2026-09-07

This record separates reproducible automated evidence from manual and
hardware-dependent release evidence. A blank item is not a pass. Simulator
results do not establish iOS background behavior, and one Mac cannot establish
the full compatibility matrix.

## Release decision

The repository owner authorized the public 2.0.0 release on 2026-09-07 with the
unchecked manual and hardware-dependent items below remaining as explicit
post-release validation. Release notes and product copy must not represent those
unchecked scenarios as verified behavior.

## Automated evidence

- [x] Shared-core and macOS Swift tests pass (135 tests total).
- [x] Repository credential scan and changed-Swift formatting verification pass.
- [x] iOS branding, callback registration, assets, simulator build, and simulator
  tests pass.
- [x] Widget extension source type-checks against the macOS SDK.
- [x] Website metadata, manifest, fragments, and asset references pass.
- [x] Release packaging and strict app-bundle verification pass with local Apple
  Development signing and with the CI-compatible ad-hoc signing path.
- [x] Brand synchronization is reproducible and leaves no unstaged source diff.

## Visual release-candidate evidence

- [x] Install the packaged 2.0.0 preview at `/Applications/Aura.app` using
  `scripts/sync-preview-app.sh` and verify its signature and bundle metadata.
- [x] Inspect the Now Playing dashboard and Appearance settings in dark mode.
- [x] Inspect the Appearance settings and theme library in light mode.
- [x] Confirm the appearance miniatures reflect the assigned Aura light and dark
  palettes and selected controls remain legible.
- [ ] Inspect every Mac navigation destination at the narrowest supported window
  size, in light and dark mode, with real, empty, error, and Private Mode states.
- [x] Inspect the website at 390-point mobile, 768-point tablet, and wide desktop
  viewports; navigation, hero copy, actions, and imagery remain legible without
  horizontal overflow.
- [ ] Inspect the iPhone app on physical hardware in light and dark mode.

## Migration and compatibility

- [ ] Upgrade a populated PresenceFM installation and verify listening history,
  settings, Last.fm credentials/session, Discord configuration, and legacy
  backups remain usable in Aura.
- [ ] Confirm the legacy PresenceFM source files remain intact after migration
  and that a second Aura launch does not repeat or duplicate imported data.
- [ ] Complete `Documentation/MANUAL-QA.md` on the oldest and newest supported
  macOS versions.
- [ ] Complete an Intel Mac run where supported hardware is available.
- [ ] Test the signed update path from the latest public PresenceFM/Aura build to
  the 2.0.0 release candidate without data loss.

## Physical-device capture matrix

For each row record device model, iOS version, Music source, start/end time, and
the redacted diagnostics filename. Count a duplicate only when Last.fm contains
more accepted scrobbles than intentional plays; count a miss only after Aura has
been relaunched, reconciled, and given network access.

| Scenario | Intentional plays | Observed | Reconciled | Review | Submitted | Missed | Duplicate | Evidence |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Foreground playback | — | — | — | — | — | — | — | Device required |
| Brief background transition | — | — | — | — | — | — | — | Device required |
| Locked / suspended | — | — | — | — | — | — | — | Device required |
| Force-quit then relaunch | — | — | — | — | — | — | — | Device required |
| Offline then reconnect | — | — | — | — | — | — | — | Device required |
| Repeat-one and manual replay | — | — | — | — | — | — | — | Device required |
| Forward and backward seek | — | — | — | — | — | — | — | Device required |
| Non-library Apple Music | — | — | — | — | — | — | — | Device required |
| Local Music file | — | — | — | — | — | — | — | Device required |
| Simultaneous Mac / iPhone | — | — | — | — | — | — | — | Provisioned two-device build required |

## Accessibility and privacy

- [ ] VoiceOver reads capture cards and navigation controls as coherent,
  actionable statements on both apps.
- [ ] Dynamic Type through the largest accessibility size preserves every iPhone
  action and essential value.
- [ ] Increased Contrast keeps selected navigation, status pills, charts, theme
  controls, and buttons legible.
- [ ] Reduce Motion removes nonessential motion without hiding state changes.
- [ ] Keyboard-only navigation reaches every Mac action with visible focus.
- [ ] Inspect final diagnostics, issue text, CSV, backup, and release-verification
  exports for credentials, usernames, listening metadata leakage, and local paths.

## Performance and distribution

- [ ] Record the four-hour mixed-provider Mac soak against
  `Documentation/PERFORMANCE.md` budgets.
- [ ] Validate CloudKit coordination using a provisioned two-device build before
  representing it as shipped behavior.
- [ ] Verify the final release DMG checksum, Gatekeeper instructions, download
  links, Sparkle signature, update enclosure URL, and clean-machine install.
- [ ] Confirm the desktop widget remains described as source-ready and is not
  embedded or represented as shipped until app-group signing is available.
