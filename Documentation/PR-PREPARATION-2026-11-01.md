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

## Cloud listen-ID collision implementation

See `CLOUD-IDENTITY-V2.md` for the end-to-end trace, compatibility activation plan
and limitations. This supersedes the earlier description of the collision as an
unimplemented code fix. New local play IDs no longer share a two-minute bucket.
The shared coordinator matches play evidence instead of accepting an ID as a
receipt, uses adjacent metadata/time lookup indices and atomic gate/index/lease
claims, and preserves old IDs/receipts without rewriting them. New cloud versions
fence old clients, while unversioned existing zones remain safely queued pending
an explicitly reviewed upgrade. No production schema or data migration was run.

The coordinator was moved into AuraCore so real decision logic can execute in
isolated macOS tests without cloud credentials. Added collision, legacy receipt,
adjacent-bucket/cross-device, short repeat, normalized-account, private-mode,
concurrent claim, stale completion, expired lease and failed-receipt tests. Local
legacy duplicate keys are blocked before submission state updates. Unknown HTTP
outcomes remain durably in-flight; accepted plays are not requeued merely because
receipt persistence fails. iOS capture anchors play start across pauses and
resets evidence on repeat-one wraps. Short repeat matching is duration-bounded.

A new disposable iOS 27 simulator reproduced the same host test execution error
seen with iOS 26.5: testmanagerd XPC listener activation reports `Operation not
permitted`, followed by the instruments lockdown/DTServiceHubClient failure. The
stalled attempt was stopped. The final companion `build-for-testing` succeeded,
including temporary-ledger regression tests, but local simulator tests have NOT
passed. A new-head CI run is required to establish simulator execution results.
Live two-device CloudKit and Last.fm acceptance remain unverified, independent
of the deterministic in-memory tests. The migration/activation plan must be
reviewed separately before existing cloud histories are enabled for version 2.

Final local Swift validation: 146 app tests plus 24 core tests (including 13 cloud
coordination regressions) passed. Strict changed-file formatting, credential scan
and patch hygiene passed. The disposable simulator created for this attempt was
shut down and deleted; existing simulators and live data were preserved.
The AGENTS-required final preview sync also passed bundle/signature verification
and installed `/Applications/Aura.app` (2.0.1, build 2026.11.03).

## Maintenance follow-up — 2026-11-04

Dependency versions and official release/advisory evidence are recorded in
`DEPENDENCY-AUDIT-2026-11-03.md`. Sparkle 2.10.1 is resolved by both SwiftPM and
Xcode; CodeQL init/analyze use 4.39.2 and upload-artifact uses 7.0.2, all actions
pinned to full commits. This incorporates the relevant bot PR changes without
merging or closing those PRs.

Confirmed fixes:
- macOS queue keys retain the full play-start instant and platform instead of a
  minute bucket, so two 40-second repeat-one plays are both admitted. Existing
  persisted keys remain unchanged; an exact legacy start/key match is still
  recognized as duplicate. No persisted history or queued row is rewritten.
- Sessions refresh late-arriving duration/metadata without discarding earned
  listening time, so a previously unknown duration can become eligible.
- Queue drains re-fetch rows after each request and skip removed/rescheduled
  rows. Completion does not mutate a row removed during the network request.
- Artwork invalidation fences in-flight downloads/catalog lookups, preventing
  late results from repopulating a cache after a refresh; cancellation remains
  checked before caching.
- Cloud coordination blocks dangling or malformed index evidence and checks the
  deterministic receipt ID directly as well as index links. Atomic lease/gate
  compare-and-save, versioned account fencing, uncertain-outcome protection and
  the reviewed activation procedure in `CLOUD-IDENTITY-V2.md` remain required.
- iOS binds scrobbles to the lease account using a username/session snapshot
  read in one Keychain actor turn. Session replacement clears identity first;
  disconnect also removes legacy fallback credentials. Account changes before
  submission release the unused lease and leave the listen queued.
- iOS HTTP 429 and API 11/16/29 are definite temporary refusals, releasing leases
  for retry instead of leaving a known refusal in uncertain submission state.
  Retry-After is finite and bounded to 5–300 seconds.
- Claude implemented the existing UI findings: Activity-only outcome filtering,
  onboarding authorization/toggle synchronization preserving explicit choices,
  actionable Discord recovery, stopped widget empty state, and website gradient
  animation/stacking. Widget remains source-only; changelog now says so.

Validation on the final implementation: Swift tests passed (151 Aura tests,
25 AuraCore tests, plus one XCTest backoff test). Formatting, credential scan,
widget source type-check and website metadata/reference checks passed. Release
packaging and the required preview sync passed strict nested code signatures,
entitlements, resources and Sparkle public-key checks using the isolated
`/tmp/Aura-PR42-Maintenance-Preview/Aura.app` target. The installed
`/Applications/Aura.app` was not replaced or terminated. DMG creation and
`hdiutil verify Aura-pr42-maintenance.dmg` passed. Release appcast signature
checks and audit thresholds were not weakened.

The new isolated iOS 26.5 / iPhone 17 Pro simulator built the test products but
failed before executing tests: “The test runner hung before establishing
connection.” The xcresult reports zero passed tests and one runner failure,
not a successful simulator suite. Result bundle:
`~/Library/Developer/XcodeBuildMCP/workspaces/PresenceFM-8f1dedb04c80/result-bundles/test_sim_2026-11-04T00-54-26-433Z_pid93528_37cedccc.xcresult`.
Three new iOS regression methods cover bounded rate limits, account-switch
session isolation with a unique test Keychain service, and refusal to submit
without a matching lease account. CI must execute these on the new head.

Remaining release gates: reviewed activation/audit of existing CloudKit zones,
real development-container two-device acceptance, and successful simulator CI
on the new head. Local fake-store tests do not prove CloudKit schema,
entitlements or Last.fm acceptance. Xcode 27/macOS 27 CodeQL tracing remains
unsupported upstream; audit CI stays on Xcode 26.0/macOS 15. No production data,
auth configuration, cloud activation, release publication or deployment was
performed. PR remains draft pending review.

### CI credential-test follow-up

The iOS simulator CI on `099131b` actually executed all 17 tests: 16 passed;
`testAccountSwitchCannotUseNewSessionForOldLease` failed with Security status
`-34018` when writing its isolated Keychain service from the unsigned test app.
This is separate from the local runner hang above. The account regression now
uses an explicit in-memory `CompanionKeychain` initializer. It runs
the same actor's session replacement, normalized account binding and disconnect
logic without requiring signing entitlements or touching any secure-storage
items. All network-client test defaults now use that isolated store too.
Production callers still use the default Security.framework initializer;
the in-memory initializer is used only by tests. No CI signing setting, test assertion, skip or
audit threshold was relaxed.

A standalone host regression compiled the same Keychain actor with DEBUG and
passed session replacement/account mismatch/disconnect checks. Formatting,
patch hygiene and the repository credential scan passed. The iOS simulator
suite must pass on the updated CI head; in-memory checks do not prove device
Keychain entitlement/access behavior.
The updated iOS app and test bundle passed `xcodebuild build-for-testing` using
the cached resolved package graph. This is compilation evidence only; simulator
execution is still delegated to CI.

### Review follow-up — receipt preservation and submission reentrancy

Passive single and batch ingestion now reject duplicate-ID ledgers before any
merge, with a regression that targets the second legacy row and checks both
in-memory listens and on-disk bytes remain unchanged. No ID repair is attempted.
Rollback requires old clients to remain disconnected: their passive cloud sync
is not fenced by the versioned lease gate.

Companion submissions now claim a MainActor per-listen slot before awaiting,
release it on every exit, then re-read the unique stored listen and private-mode
state. Stale queued copies cannot resubmit a completed listen in local-only mode.
Configuration failures and CancellationError from the pre-request rate-slot
sleep release/requeue the unused lease; URLSession transport cancellation remains
an uncertain outcome. Claude clarified the history action as Export Local
History, hid it on the Last.fm tab, and documented that remote scrobbles are not
included. The existing local period/search/outcome filters are preserved.

The iOS app and expanded test bundle compiled successfully. Formatting,
credential scan and patch hygiene passed. Local simulator execution is not
claimed; updated regression execution awaits CI. The required macOS preview
sync uses `/tmp/Aura-PR42-Followup/Aura.app` rather than `/Applications`.

The `d54583f` simulator job executed 17 tests with one failure in the new
in-memory preservation assertion. Its pre-encoding fixture had fractional
`capturedAt` dates, while the ledger ISO-8601 round trip removes fractional
seconds. The regression now compares pre/post-operation **decoded** snapshots,
as well as retaining the exact on-disk byte comparison and all expected-error
assertions. This fixes the test baseline without changing ledger serialization
or duplicate-ID handling. Simulator success on the corrected head awaits CI.

## Release preparation follow-up from 71ec104 (November 4)

- Added an actual macOS WidgetKit extension target to the workspace and release
  package. Build unsigned, embed under `Contents/PlugIns`, sign extension before
  host, retain host/Sparkle signature checks. Verify extension metadata, version,
  sandbox, app group and signing team. Real signing requires explicit compatible
  host/widget provisioning profiles; no developer-account configuration changed.
- Redact widget track/artist/platform/progress before persisting Private Mode
  snapshots, with regression coverage. Keep the existing shared suite.
- Added an offline CloudKit compatibility-plan primitive with no network or
  production call site, preserving receipts and system fields, preparing index
  additions plus a paused fenced gate, rejecting unresolved records. Expanded
  isolated two-client tests through activation/resume/repeat/pause. Added a
  read-only exported-schema field checker and rejection tests, run in CI.
- Validation: 152 Aura tests + 27 AuraCore tests + 1 XCTest = 180 passing Swift
  tests; four Python script tests; credential scan, formatting and diff hygiene.
  Actual widget extension built successfully. Ad-hoc packaged app and extension
  passed deep/strict signatures and package checks, including isolated preview
  sync to `/tmp/aura-release-preparation/Aura.app`; installed app untouched.
  Current iOS test products build unsigned via XcodeBuildMCP. This is explicitly
  **not a simulator test pass**. Baseline 71ec104 had successful actual simulator
  tests in CI; new-head CI must execute them again. Local simulator execution
  remains affected by the previously documented runner/XPC issue.
- Read-only access diagnosis: `cktool` installed, `get-teams` reports no management
  token; no compatible local provisioning profiles or Developer ID identity.
  Therefore live schema/export compatibility, real app-group/gallery acceptance
  and physical two-device CloudKit/Last.fm acceptance remain unverified. No live
  records, schema, auth settings or production configuration were changed.
- Keep draft. See WIDGET.md for provisioning/hardware acceptance and
  CLOUD-IDENTITY-V2.md for exact read-only checks, staging, CAS activation,
  pause/resume and the prohibition on reverting the old-client fence. The
  independent Mac scrobble queue still does not participate in companion cloud
  deduplication; do not claim whole-product exactly-once delivery.

### Follow-up to review 5778060393

- Added signing-certificate authorization against each profile's
  DeveloperCertificates, both for the chosen identity before signing and the
  actual extracted host/widget leaf certificates afterward. Standalone package
  verification checks provisioned artifacts too. Renewed/missing certificate
  fixtures are rejected; existing entitlement/team/expiry checks remain.
- Restricted duplicate-ID ingestion refusal to evidence that could affect a
  collision. Unrelated capture continues; an affected batch rolls back fully in
  memory and on disk. Corrections now reject ambiguous IDs too. No local IDs or
  receipts are automatically renamed/discarded. Recovery remains the explicit
  backed-up compatibility procedure, not the normal Reconcile action.
- Companion retry classification now releases definite connection-establishment
  failures while preserving unknown outcomes for timeouts, lost connections,
  URLSession cancellation and malformed responses. API requests refuse redirects
  so a connection error at a redirected endpoint cannot justify retrying the
  original POST. Added error classification, mocked transport, redirect refusal
  and atomic-ingestion regression checks.
- Documented implicit NUMBER field review and separately approved schema typing;
  unqualified NUMBER remains rejected, with a regression assertion.
- Validation: four Python script tests passed; thirteen companion XCTest cases
  passed in a temporary macOS harness using the actual store/client/keychain
  source (only unused iOS framework imports omitted; MusicKit-only cases excluded).
  This is host execution, not iOS Simulator execution or live-service acceptance.
  Unsigned iOS test products built successfully. Ad-hoc package verification and
  isolated sync passed under /tmp; installed app unchanged. Formatting, secret
  scan and patch hygiene passed. Baseline 3b5ddfa's repository hygiene/actual iOS
  simulator and package CI passed; the new head must run CI again.
