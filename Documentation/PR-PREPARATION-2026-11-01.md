# Aura working-tree recovery and PR preparation

The original `release/2.0.1-preparation` tip is preserved as
`backup/aura-before-reconcile-20261101`. All tracked and untracked product work
was checkpointed in `3f92eb1` before reconciliation. An additional binary patch
and untracked archive were saved outside the repository in `/tmp/aura-preservation`.

The former release tip `aae2c57` and fetched `origin/main` (`1a480de`, squash #28)
had identical trees. The reconciliation merge retains the newer preserved work
when Git reports overlapping squash-history conflicts. No remote branch was
force-pushed, and no release tag or deployment was made.

The preserved changes cover asynchronous cancellable artwork, repeat-one session
tracking, Last.fm retry timing, Discord timestamps and reconnection, atomic
credential updates, CloudKit submitted-listen protection, and the Mac dashboard,
shared design system, widget and website refresh.

Dependency scope: inspected open Sparkle patch PR #39 (2.10.1), including its
manifest-only lockfile change and passing existing CI/package checks. It remains
separate. Actions updates #34, #40 and #41 do not affect these implementation
changes and remain untouched.

Production readiness still requires the manual accessibility, real-provider soak,
populated-install upgrade, hardware CloudKit coordination, and signed update
checks listed in `QA-2.0.1.md`. Simulator and unit checks cannot establish those.

## Finishing changes and local validation

Claude reviewed the UI and fixed the narrow-window Insights grid, Quick Open
hover scrolling, onboarding's empty provider selection, and reopened-guide Escape
behavior. The widget now has a Mac URL handler and packaging registers `aura`;
bundle verification checks that registration. Integration finishing also removes
an implicit-capture compiler warning and formats the preserved Swift changes.

- `swift test`: 143 app tests in 20 suites and 11 core tests passed.
- Changed-file strict Swift formatting, website metadata/assets/fragments,
  credential scan, widget source type-check and patch hygiene passed.
- `scripts/sync-preview-app.sh`: rebuilt, verified and installed final preview at
  `/Applications/Aura.app` (2.0.1, build 2026.11.02).
- iOS simulator build passed with cached package resolution. The ordinary script
  stalled at package resolution for over eight minutes and was stopped. A test
  retry without the script's native-architecture restriction hit x86_64 linker
  errors; the native arm64 test retry is recorded separately below.

The optional correction-sheet error message and immediate Discord text-field
updates remain follow-ups; neither was expanded into this already broad change.
The widget extension remains source-checked only and is not embedded in the
shipping app (see `WIDGET.md`).

The arm64 iOS test build completed, but test execution could not connect to
`com.apple.instruments.deviceservice.lockdown`: `DTServiceHubClient failed to
bless service hub` for the available iPhone 17 Pro simulator. This is an
unresolved local simulator execution blocker, not an iOS test pass. Re-run the
companion script on a healthy simulator/CI before considering release readiness.
The installed Mac preview also passed a demo launch smoke check.

## Privacy and reliability follow-up

- Restored `discordSharePaused` to false only when the preference is absent.
  Existing saved true/false choices remain intact. Balanced is private by default;
  Minimal remains false and Detailed retains its deliberate true preset. Tests
  cover absent-key non-persistence, saved choices, toggles/reload, and profile
  application/serialization.
- YouTube Music now preserves failed/inactive provider health between network
  polls instead of reporting a false recovery. The transport test covers a lost
  connection, repeated cached failures, and successful reconnection.
- Last.fm HTTP 429 delays are bounded to 5–300 seconds, with a 30-second fallback
  for malformed/non-finite values. Parameterized transport tests include normal,
  excessive, infinite, NaN, negative and invalid headers.
- Full `swift test`: 146 app tests in 20 suites plus 11 core tests passed. The
  existing stalled-artwork transition, repeat-one, seek and queue retry coverage
  also passed. Formatting, credential scanning and patch hygiene passed.
- The AGENTS-required preview sync rebuilt, verified and installed the preview.
  No UI changes, tag, merge, force push or release publication were performed.

### iOS verification and unresolved release risks

The prior PR head (`4a4205a`) passed the complete companion verification script
on GitHub CI: run 41383757440, job 125079966462, logged the simulator verification
success at 2026-11-02 03:42:18 UTC. iOS sources are unchanged by this follow-up.
Local XcodeBuildMCP successfully prepared the simulator test products, but execution
again stalled on the iOS 26.5 iPhone 17 Pro. Device logs show `testmanagerd`'s XPC
listener failing with `Operation not permitted`, and xcodebuild reports
`DTServiceHubClient failed to bless service hub` for the instruments lockdown
service. The stalled run was stopped and the existing simulator rebooted without
erasing its data for one more execution attempt. This is an environment diagnosis,
not evidence of a failing app assertion.

A separate confirmed CloudKit identity risk remains: `CanonicalListenIdentity`
uses a 120-second bucket while the merger separates plays over 90 seconds apart.
Distinct plays 91–119 seconds apart in one bucket can share an ID and be suppressed
by the already-submitted guard. A cross-device identity/migration design and
hardware coordination tests remain necessary before claiming production readiness;
this follow-up does not change persisted identity semantics.

The post-reboot attempt reproduced the same XPC listener permission failure and
was stopped. Local iOS test execution remains blocked; no app assertion failure
was observed. The previous head's CI pass is historical validation, not a pass
for the follow-up head.
