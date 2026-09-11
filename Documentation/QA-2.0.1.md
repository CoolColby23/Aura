# Aura 2.0.1 Mac release preparation

Validation performed September 10–11, 2026 on Apple silicon, macOS 27.0
(26A428). This is a local preview, not a published release.

## Scope

The owner discontinued iPhone work during this pass. Existing iOS edits are
preserved; iPhone hardware checks and cross-device CloudKit coordination are
excluded from this Mac release. No widget distribution or notarization is claimed.

## Completed evidence

- [x] `swift test`: 125 Mac Swift Testing tests, 10 shared-core tests, and one
  XCTest pass (136 total). Includes migration fixtures, preserving legacy files,
  credential adoption, backup/restore, privacy redaction, duplicate prevention,
  seeking, provider selection, and queue recovery. Fixtures do not establish a
  complete real-install upgrade.
- [x] Changed-Swift formatting, repository credential scan, website verification,
  widget source type-check, and `git diff --check` pass.
- [x] `scripts/sync-preview-app.sh` installs and verifies version 2.0.1,
  build 2026.09.11 at `/Applications/Aura.app`.
- [x] Local Apple Development-signed preview installer created as
  `Aura-2.0.1-preview.dmg`; disk-image integrity and its SHA-256 file verify.
- [x] Visual inspection of Mac Now Playing (empty and demo), populated local
  History, empty Pending Plays, Status & Support, Appearance, and Quick Open.
  Light-mode Now Playing and Appearance and dark-mode main destinations were
  inspected. This does not cover every state or the minimum window size.
- [x] Correct low-contrast accent headings and hero controls using the existing
  appearance-aware readable accent. Remove the unconditional iCloud-sync claim.
- [x] Implement Quick Open Return activation and Escape dismissal. Installed-preview recheck on September 11 passed: typing History and pressing
  Return navigates to History and dismisses the palette; reopening and pressing
  Escape dismisses it without changing the destination.
- [x] Download the public 2.0.0 DMG, verify its published SHA-256 and disk image,
  and cryptographically verify its Ed25519 enclosure signature using the update
  public key bundled in Aura. Enclosure length also matches the archive.

## Performance observation

A five-minute demo run sampled the running app with `ps` every five seconds
while UI automation and build work were active. Sixty samples reported 17.29%
average CPU, 35.3% peak CPU, 92.42 MiB average resident memory, and 137.02 MiB
peak resident memory. The CPU observation exceeds the documented 3% playing
budget. `ps` CPU values and concurrent inspection are not an isolated benchmark;
repeat idle and normal playback measurements without UI automation or builds
before drawing a performance conclusion. No performance pass is claimed.

## Remaining before a fully validated production release

- [ ] Isolated five-minute idle/playing measurements and the four-hour
  mixed-provider soak in `PERFORMANCE.md`, including real offline recovery,
  seek, repeat, provider switching, Discord restart, and Private Mode.
- [ ] Complete human VoiceOver, keyboard focus, Increased Contrast, and Reduce
  Motion checks, plus all destinations at minimum window size.
- [ ] Real populated-install upgrade and signed Sparkle update/install test,
  including a clean-machine first launch and oldest supported macOS.
- [ ] Commit/review the intended Mac changes and run the release workflow to
  build the distribution artifact and signed 2.0.1 appcast. Verify that exact
  archive before publishing. No tag, push, or publication was performed here.

The local preview intentionally uses a date-based build number ahead of the
production feed. Do not upload this preview as a production Sparkle update;
use the release workflow's monotonically increasing build number instead.
Developer ID signing/notarization remain unavailable: only Apple Development
identities were found. The documented ad-hoc distribution path remains in use.

## Branch preparation recheck — September 11

- All 136 tests passed again with `swift test`.
- Changed-Swift formatting, credential scan, website verification, widget
  source type-check, and branch patch hygiene passed again.
- Rebuilt, signature-verified, and installed the 2.0.1 (2026.09.11) preview
  using `scripts/sync-preview-app.sh`.
- Preserved iOS source cleanup in a separate commit from the Mac UI changes.
- Existing iOS companion verification passed, including simulator tests; this
  preserves CI coverage and does not establish iPhone hardware readiness.
