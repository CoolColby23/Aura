# Aura 1.3.0 Validation Record

Updated: 2026-08-25

Automated checks and physical-device evidence are recorded separately. A blank
measurement is not a pass, and simulator results must not be used as evidence of
iOS background execution.

## Automated evidence

- [x] Shared-core and macOS Swift tests pass.
- [x] iOS simulator tests cover Last.fm pagination bounds and deduplication,
  concurrent request spacing, and corrected-ledger validation.
- [x] iOS branding, callback registration, asset integrity, and simulator build pass.
- [x] Changed Swift files pass the repository formatter.
- [x] Website references and callback bridge pass integrity checks.
- [x] Release packaging and strict app-bundle verification pass using ad-hoc signing.
- [x] Repository credential scanning passes.

## Physical-device capture matrix

For each row record device model, iOS version, Music source, start/end time, and
the redacted diagnostics filename. Count a duplicate only when Last.fm contains
more accepted scrobbles than intentional plays; count a miss only after the app
has been relaunched, reconciled, and given network access.

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
| Simultaneous Mac / iPhone | — | — | — | — | — | — | — | Provisioned CloudKit build required |

## Accessibility and presentation

- [ ] VoiceOver reads each capture card as one coherent statement.
- [ ] Dynamic Type through the largest accessibility size preserves every action.
- [ ] Increased Contrast keeps selected tabs, status pills, charts, and buttons legible.
- [ ] Reduce Motion removes nonessential transitions without hiding state changes.
- [ ] Denied Music access offers Open Settings; Check Again never opens Settings.
- [ ] Locked, suspended, and force-quit copy describes iOS limitations truthfully.

## Mac compatibility and soak

- [ ] Complete `Documentation/MANUAL-QA.md` on the oldest and newest supported macOS versions.
- [ ] Complete an Intel run where supported hardware is available.
- [ ] Record a four-hour mixed-provider soak using `Documentation/PERFORMANCE.md` budgets.
- [ ] Inspect the final diagnostics and release-verification exports for personal data.
