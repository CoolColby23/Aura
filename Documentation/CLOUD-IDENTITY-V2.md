# Cloud listen identity v2: compatibility and verification

## Trace and failure

The companion ledger used `SHA256(sourceTrackID | floor(start / 120))` as
both a local row key and the CloudKit Listen record name. Evidence merge accepts
normalized title/artist with starts within 90 seconds. Plays at 2041 and 2140
seconds therefore were separate merge decisions with the same ID. Local state
updates selected the first such ID, and the cloud already-submitted check could
silently acknowledge the second play using the first play's receipt.

`deviceID` identifies observers, not a play. Catalog IDs may differ across devices
or local libraries. The Mac currently submits through its independent
`PlaybackSessionTracker` / `ScrobbleQueue`, not `CloudSubmissionCoordinator`.
This change fixes the companion/shared coordination path; it does not claim that
the independent Mac queue participates in cross-device CloudKit deduplication.

## New behavior

- New local ledger keys are versioned hashes of source, normalized metadata and full start timestamp,
  without time buckets. Existing stored keys are never recomputed or rewritten.
  Evidence merge uses normalized title/artist and a 90-second maximum policy
  bounded to half the shorter known track duration for short-track repeats;
  multiple candidates require review rather than choosing the first source-ID
  match. Two existing rows with one legacy key cannot be updated individually:
  submission is blocked before sending, preserving the file for reconciliation.
- Cloud lookup is separate from local IDs. Three metadata/time indices (the
  current two-minute bucket and its neighbors) link to actual play records. The
  indices ignore device and catalog IDs. Matching requires metadata and start
  proximity, never an ID alone. Legacy keys from every supplied evidence item
  and adjacent buckets are inspected too. Multiple matches, missing metadata,
  missing receipts, or ambiguous account ownership fail closed.
- Cloud indices use the existing `Listen` record type with an additive
  `listenIDs: [String]` field. Play records add `username` and `leaseToken`.
  Metadata and existing receipts are not overwritten by passive capture.
  Raw evidence stays in the local ledger; old cloud Evidence records are retained.
- The existing private-database Aura zone and global SubmissionGate still
  establish one Last.fm account per zone. Account comparison trims whitespace
  and ignores case. The gate's `coordinationVersion` must be 2. Its versioned
  username (`aura-coordination-v2:<normalized username>`) prevents old binaries'
  literal username checks from acquiring new leases. A bare legacy username
  blocks the new coordinator rather than being upgraded silently.
- Resolving a play, adding its index link, claiming its lease and changing the
  gate generation are one atomic `.ifServerRecordUnchanged` batch. Concurrent
  contenders cannot create two cloud records for the same match: one must
  re-resolve after a conflict. Same-device reentry is also rejected. Completion
  requires a per-attempt token, device and account; stale completion cannot clear
  a newer lease. Expired in-flight leases are uncertain, not automatically stolen.
- Last.fm acceptance is persisted locally before publishing the cloud receipt.
  Receipt-write failure never enters the scrobble retry path. Definite Last.fm
  deferrals may release/requeue; transport/unknown responses retain `.submitting`
  locally and in the cloud. They require outcome reconciliation. Last.fm provides
  no application idempotency key, so exactly-once delivery across a crash/network
  failure cannot be promised. This policy preserves uncertain work without
  blindly resending it.

The iOS observer now anchors a play's start instead of sliding it forward during
pauses, and resets accumulated evidence on a detected repeat-one wrap. The merge
and cloud windows both distinguish normal short-track repeats from one play.

## Compatibility / rollout plan — NOT executed on live data

1. Stop older cloud-enabled clients and wait for in-flight attempts to settle.
   Export/back up the local ledgers and private Aura zone. Do not delete either.
2. Validate additive CloudKit fields in an isolated development container:
   `SubmissionGate.coordinationVersion` (Int64), `Listen.listenIDs` (String list),
   `Listen.username` and `Listen.leaseToken` (String), and `Listen.duration` (Double). Review schema promotion
   separately. This PR does not deploy a production schema.
3. Audit existing local duplicate IDs and cloud receipts against stored evidence
   and Last.fm history. Do not infer that a second play was accepted just because
   its ID collides. Preserve unknown outcomes for review; do not auto-resubmit.
   In particular, submitted legacy rows with overwritten metadata cannot be
   repaired confidently from their current record alone.
4. Prepare cloud metadata/time index links for **all** known legacy play records,
   including those whose catalog IDs differ by device. Preserve record names,
   receipts and state; do not replace them with empty v2 records. Missing account,
   metadata or acceptance information requires human reconciliation. Any local
   key repair must also be an explicitly reviewed, backed-up operation, not a
   startup migration. No migration tool or live mutation is run by this PR.
5. Only after that audit, atomically activate the existing gate with version 2
   and the versioned username. New code deliberately blocks unversioned zones.
   The versioned username fences old lease acquisitions, but cannot cancel an
   old HTTP request already in flight; that is why quiescence is mandatory.
6. Verify two physical devices in the development container before separately
   approving any production upgrade. Rollback to an old binary must keep the
   gate fenced; do not strip its versioned username and resume blind submissions.

An empty newly created zone can initialize v2 directly. Existing unversioned
zones remain queued until the above reviewed compatibility upgrade. Local-only
builds do not create or migrate cloud data. Account switching in one zone is
intentionally blocked; an account-history migration is a separate operation.

The 90-second matching policy is still a heuristic, not proof that independent
simultaneous listens are one play. Unrelated Mac submissions, seeks/restarts inside that matching tolerance, and simultaneous independent listening need a
broader capture/session design before making stronger cross-device guarantees.

## Verification limits

`CloudCoordinationTests` runs the production coordinator against an in-memory
record store that models independent snapshots and atomic compare-and-save. It
never constructs CKContainer or contacts CloudKit. Coverage includes collisions,
legacy keys/receipts, adjacent buckets, device/source variations, account/private
mode gates, concurrent acquisition, stale completion, expired/unknown leases and
failed receipt persistence. These tests validate decision logic, not production
CloudKit schema, entitlements, network behavior or Last.fm acceptance.

Companion store tests use temporary ledgers and check repeat-play persistence and
refusal to update a duplicate legacy key. iOS build/test results are recorded in
the PR preparation document. Build-for-testing is not a simulator test pass.
