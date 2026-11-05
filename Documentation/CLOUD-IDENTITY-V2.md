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
  passive single/batch evidence ingestion that could touch those colliding rows
  and submission of those rows are blocked before selecting a row. Unrelated
  evidence can still be ingested; a batch containing a collision rolls back
  every staged change. Metadata corrections also reject ambiguous IDs. Back up duplicate-ID ledgers before running any new client;
  reconcile them separately rather than relying on an ID-only merge. No repair
  or migration is performed by capture.
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
   gate fenced and keep all old clients disconnected from the zone. Older
   capture flows call passive sync before acquiring a lease; the gate cannot
   prevent that sync from overwriting receipt metadata/state. Do not reconnect
   old clients or strip the versioned username during rollback.

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

## Read-only schema verification and reversible activation procedure

Use Apple's [text schema workflow](https://developer.apple.com/documentation/cloudkit/integrating-a-text-based-schema-into-your-workflow)
and export the **existing** schema, retaining every existing type, field, index
and permission. The requirements checker is deliberately not an importable
replacement schema. It cannot prove private-zone ownership or record contents.

An implicitly created numeric field may export as unqualified `NUMBER`. The
checker deliberately rejects it because the export does not establish whether
it is intended as `INT64` or `DOUBLE`. Review the field's intended semantics and
existing values, prepare a separate schema change using `NUMBER PREFERRED AS
INT64` or `NUMBER PREFERRED AS DOUBLE` as appropriate, obtain approval, validate
it in the isolated development container, then re-export and rerun this checker.
Do not silently infer a type, edit a production schema, or use this checker to
apply that change. Existing preferred types must not be changed.

With an already configured management token in the keychain/environment:

```sh
xcrun cktool export-schema --team-id "$TEAM_ID" --container-id "$CONTAINER_ID" \
  --environment development --output-file /tmp/aura-development.ckdb
python3 scripts/verify-cloud-schema.py /tmp/aura-development.ckdb
xcrun cktool validate-schema --team-id "$TEAM_ID" --container-id "$CONTAINER_ID" \
  --environment development --file /tmp/aura-development.ckdb
```

Production schema export/validation is also read-only, but never run import,
reset, promotion or record mutation as part of this PR. For isolated schema
experiments use a separately approved disposable container, not production.
On this machine `cktool get-teams` reports **no management token**; no schema was
exported or verified remotely. No compatible provisioning profiles are present.
Schema access remains an explicit external blocker, not a passed test.

`CloudCompatibilityPlan` is an internal, offline preparation primitive, exercised
against the isolated record store. It has no database or production call site.
Given a full reconciled export of the global gate and all Listen records, it
prepares additive index records and a **paused** v2 gate. It copies CloudKit
system fields/change tags, preserves existing index links, leaves play records
and receipts untouched, normalizes the selected account, and rejects missing
ownership, missing submitted receipts, leases/unknown outcomes, duplicate record
IDs, dangling links and invalid metadata. Missing legacy owners must be resolved
from independent evidence by the operator; the planner never invents them.
It cannot establish export completeness or detect historically overwritten
metadata. Those remain prerequisites to any separately authorized migration.

The exact future activation sequence is:

1. Quiesce **all** clients (including passive writers and the independent Mac
   Last.fm queue), settle/reconcile HTTP outcomes, record client versions and
   snapshot time. Back up local ledgers and a complete paginated private-zone
   export including CloudKit system fields/change tags. Record counts/checksums;
   keep backups private and encrypted. Resolve duplicate local keys separately.
2. Validate the additive schema with the commands above. Reconcile every legacy
   row/account/receipt against evidence and Last.fm. Run the offline planner on
   that complete reconciled snapshot. Review its index-only diff and paused gate.
   Do not activate if any unresolved row, omitted page or uncertain outcome exists.
3. In an isolated container first, save the paused, version-fenced gate with
   `.ifServerRecordUnchanged`. Stage index additions in bounded batches below
   CloudKit's operation limits, preserving all old links and records. Reread
   **all** indices and play receipts, and compare counts, links and original
   receipt checksums. A partial staging failure stays paused; resume staging
   after re-export/review rather than erasing the gate or replaying HTTP calls.
4. Re-export and revalidate the gate after staging. Only after two-client tests
   and separate release authorization, CAS `privateMode=false` with incremented
   generation/effective time, keeping version 2 and the versioned username.
   Launch supported clients one at a time and verify an existing submitted play
   stays submitted, new repeats remain distinct and one claim wins per play.
5. To pause/roll back, CAS `privateMode=true`, increment generation and record
   effective time. This blocks new claims, but an already owned HTTP attempt
   may finish: settle it and retain its receipt. Keep clients quiesced, all
   records/indices/backups and the versioned username. Never restore the bare
   username, downgrade the gate, reconnect old clients or delete accepted plays.
   Resume by rerunning the audit and step 4; no inverse data rewrite is needed.

The isolated regression now executes this paused-plan → explicit resume → old
receipt observed by a different catalog/device → repeated play accepted → pause
sequence with two independent coordinator instances. Existing tests exercise
simultaneous CAS claims, expired unknown attempts, stale tokens, account/privacy
fences and receipt-write retry. This is protocol simulation, not two physical
devices, live CloudKit transaction acceptance or real Last.fm submission.

### Legacy local collision recovery remains explicit

A collision no longer disables unrelated capture. A batch that includes an
affected play remains atomic and does not advance its reconciliation cursor.
Approve, dismiss and correction by a duplicated ID stay blocked: those actions
cannot distinguish which row owns an existing cloud receipt. No in-app rename or
mass dismissal is introduced as an implicit repair. Stop affected clients, back
up their full ledgers, and follow the complete receipt/evidence audit and staged
compatibility procedure above with a maintainer. An individually reviewed local
repair must preserve original IDs/evidence/receipts in the backup and establish
the mapping to cloud records before any retry. Unknown outcomes remain fenced.
This PR deliberately does not execute that data migration or claim the ordinary
Reconcile action repairs legacy collisions.
