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
