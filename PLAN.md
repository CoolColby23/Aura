# Aura Project Plan

This file tracks forward-looking outcomes. Shipped work belongs in
`CHANGELOG.md`; release evidence belongs in `Documentation/QA-*.md`.

Status notation: `[ ]` planned, `[-]` in progress or partially verified, and
`[x]` complete.

## Next release — 2.0.1 (Mac)

The owner discontinued iPhone work on 2026-09-10. Existing iOS source is retained,
but physical iPhone QA and Mac/iPhone coordination are outside this release.

- [x] Consolidate Mac component measurements and screen spacing.
- [x] Improve dark-mode accent legibility and Quick Open keyboard activation.
- [x] Remove the unconditional iCloud theme-sync claim from Appearance.
- [x] Prepare and verify the local preview and installer; evidence and remaining
  release checks are recorded in `Documentation/QA-2.0.1.md`.

## Previous release — 2.0.0

Version 2.0 renames PresenceFM to Aura, introduces the Aura halo and adaptive
theme system across Mac, iPhone, web, and widget source, and preserves existing
stores, credentials, Keychain items, and backups through the transition.

- [x] Rename product targets, bundle identifiers, project files, documentation,
  packaging, and public copy from PresenceFM to Aura.
- [x] Add the Aura visual system and apply its semantic colors, continuous
  rounding, and theme-aware selection treatment across Mac and iPhone.
- [x] Migrate the legacy listening store, credentials, iPhone Keychain items,
  and backup-file compatibility without deleting the originals.
- [x] Consolidate canonical brand source and generated deliverables, add website
  icons and a web manifest, and type-check widget source in CI.
- [x] Pass automated Mac, shared-core, iOS simulator, website, credential-scan,
  widget-source, and package verification for the 2.0 release candidate.
- [-] Continue the manual and hardware-dependent validation recorded in
  `Documentation/QA-2.0.0.md`; the public release must not imply that unchecked
  scenarios have been verified.

## Next

- [ ] Complete real-provider Mac offline recovery, seek, repeat, local-file,
  and provider-switching checks and record them in `Documentation/QA-2.0.1.md`.
- [ ] Finish a human VoiceOver, increased-contrast, reduced-motion, and Dynamic
  Type pass on the Mac app.
- [ ] Run and record the four-hour mixed-provider Mac soak test against the
  budgets in `Documentation/PERFORMANCE.md`.
- Cross-device CloudKit validation is deferred with the iPhone app; it is not a
  2.0.1 release claim.
- [ ] Add Developer ID signing and notarization if sustainable credentials become
  available; retain the documented ad-hoc distribution path otherwise.

## Exploring

- Localization after interface copy and accessibility labels stabilize.
- Additional playback providers only when their APIs permit deterministic,
  privacy-preserving behavior.
- App-group-backed widget distribution after Apple-signed entitlement testing;
  the 2.0 release contains source only and does not claim the widget as shipped.

## Planning principles

- Privacy remains the default: no Aura account, backend, analytics, or
  uploaded listening history.
- Failed network work must be bounded, deduplicated, recoverable, and safe to retry.
- New behavior must be testable without live credentials whenever practical.
- Compatibility, accessibility, migration safety, and truthful capability claims
  are release requirements.

## Historical plans

Completed milestones and accepted limitations are retained in
`Documentation/ROADMAP-ARCHIVE.md`, the versioned QA records, `CHANGELOG.md`, and
Git history.
