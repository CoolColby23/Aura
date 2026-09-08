# Aura Project Plan

This file tracks forward-looking outcomes. Shipped work belongs in
`CHANGELOG.md`; release evidence belongs in `Documentation/QA-*.md`.

Status notation: `[ ]` planned, `[-]` in progress or partially verified, and
`[x]` complete.

## Current development — 1.3.0

Version 1.3 adds the source-built iPhone companion, user-confirmed Apple Music
history scrobbling, shared capture-status language, and stronger Mac queue
recovery.

- [x] Share deterministic capture evidence, eligibility, merge, submission, and
  status-presentation rules across Mac and iPhone.
- [x] Keep iPhone credentials in Keychain and support a local-only personal-team
  build without CloudKit entitlements.
- [x] Add paginated Last.fm history, explicit historical-import review, reports,
  charts, and queue-recovery interfaces.
- [x] Add deterministic simulator tests for iPhone ledger correction, Last.fm
  pagination, deduplication, and concurrent request spacing.
- [x] Add Swift security analysis and changed-file formatting to CI.
- [-] Complete the physical-device capture matrix in
  `Documentation/QA-1.3.0.md` before making public reliability claims.

## Next

- [ ] Complete foreground, locked, suspended, force-quit, offline, seek, repeat,
  local-file, and simultaneous-device measurements on physical hardware.
- [ ] Finish a human VoiceOver, increased-contrast, reduced-motion, and Dynamic
  Type pass on both apps.
- [ ] Run and record the four-hour mixed-provider Mac soak test against the
  budgets in `Documentation/PERFORMANCE.md`.
- [ ] Validate CloudKit coordination using a provisioned two-device build before
  representing it as shipped behavior.
- [ ] Add Developer ID signing and notarization if sustainable credentials become
  available; retain the documented ad-hoc distribution path otherwise.

## Exploring

- Localization after interface copy and accessibility labels stabilize.
- Additional playback providers only when their APIs permit deterministic,
  privacy-preserving behavior.
- App-group-backed widget distribution after Apple-signed entitlement testing.

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
