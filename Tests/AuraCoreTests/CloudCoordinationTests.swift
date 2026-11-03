import CloudKit
import Foundation
import Testing

@testable import AuraCore

struct CloudCoordinationTests {
    let start = Date(timeIntervalSince1970: 2_040)  // bucket boundary

    func listen(_ offset: TimeInterval = 0, source: String = "catalog", device: UUID = UUID(), legacy: Bool = false, duration: TimeInterval = 180)
        -> CanonicalListen
    {
        let evidence = PlaybackEvidence(
            deviceID: device, sourceTrackID: source,
            metadata: .init(title: "Track", artist: "Artist", duration: duration, startedAt: start.addingTimeInterval(offset)),
            observedPlayTime: 120, origin: .observed, confidence: .strong)
        return CanonicalListen(
            id: legacy ? CanonicalListenIdentity.legacy(for: evidence) : CanonicalListenIdentity.make(for: evidence), evidence: [evidence],
            metadata: evidence.originalMetadata, state: .queued)
    }

    func coordinator(_ store: IsolatedCloudStore, device: UUID = UUID(), account: String = "listener", time: Date? = nil) -> CloudSubmissionCoordinator {
        let clock = time ?? start
        return CloudSubmissionCoordinator(database: store, deviceID: device, now: { clock }, username: { account })
    }

    @Test func identityMetadataNormalizationIsLocaleIndependent() {
        #expect("İSTANBUL".presenceNormalized == "istanbul")
        #expect("  CÁFÉ—Track  ".presenceNormalized == "cafe track")
    }

    @Test func repeatedPlaysNoLongerShareLedgerOrCloudReceipt() async throws {
        let first = listen(1), repeatPlay = listen(100)
        #expect(CanonicalListenIdentity.legacy(for: first.evidence[0]) == CanonicalListenIdentity.legacy(for: repeatPlay.evidence[0]))
        #expect(first.id != repeatPlay.id)
        #expect(DefaultEvidenceMerger().merge(repeatPlay.evidence[0], into: [first]) == .newListen(repeatPlay.id))
        let store = IsolatedCloudStore()
        let cloud = coordinator(store)
        try await cloud.prepare()
        let lease = try await cloud.acquireLease(for: first)
        try await cloud.complete(lease, result: .accepted(start))
        let secondLease = try await cloud.acquireLease(for: repeatPlay)
        #expect(secondLease.listenID != lease.listenID)
        try await cloud.complete(secondLease, result: .accepted(start))
        #expect(await store.submittedCount() == 2)
    }

    @Test func shortTrackRepeatsDoNotMergeInsideNinetySeconds() async throws {
        let first = listen(1, duration: 40), second = listen(41, duration: 40)
        #expect(DefaultEvidenceMerger().merge(second.evidence[0], into: [first]) == .newListen(second.id))
        let store = IsolatedCloudStore(), cloud = coordinator(store)
        try await cloud.prepare()
        let lease = try await cloud.acquireLease(for: first)
        try await cloud.complete(lease, result: .accepted(start))
        let next = try await cloud.acquireLease(for: second)
        #expect(next.listenID != lease.listenID)
    }

    @Test func crossDeviceSourceIDsAndAdjacentBucketsReuseReceipt() async throws {
        let store = IsolatedCloudStore()
        let a = coordinator(store), b = coordinator(store)
        try await a.prepare()
        let first = listen(-1, source: "catalog"), second = listen(1, source: "local-library")
        #expect(first.id != second.id)
        let lease = try await a.acquireLease(for: first)
        try await a.complete(lease, result: .accepted(start))
        do { _ = try await b.acquireLease(for: second); Issue.record("Duplicate submission allowed") } catch CloudCoordinationError.alreadySubmitted(let date) {
            #expect(date == start)
        }
        #expect(await store.submittedCount() == 1)
    }

    @Test func legacyReceiptIsPreservedButDoesNotSuppressDifferentPlay() async throws {
        let store = IsolatedCloudStore()
        let cloud = coordinator(store)
        try await cloud.prepare()
        let old = listen(1, legacy: true)
        try await store.seedLegacy(old, account: "listener", submitted: start)
        do { _ = try await cloud.acquireLease(for: old); Issue.record("Legacy play submitted twice") } catch CloudCoordinationError.alreadySubmitted {}
        let replay = listen(100)
        let lease = try await cloud.acquireLease(for: replay)
        #expect(lease.listenID != old.id)
        #expect(await store.record(old.id)?["submittedAt"] as? Date == start)
    }

    @Test func persistedLegacyCollisionUsesMetadataNotID() async throws {
        let store = IsolatedCloudStore()
        let cloud = coordinator(store)
        try await cloud.prepare()
        let old = listen(1, legacy: true), replay = listen(100, legacy: true)
        #expect(old.id == replay.id)
        try await store.seedLegacy(old, account: "listener", submitted: start)
        let lease = try await cloud.acquireLease(for: replay)
        #expect(lease.listenID != old.id)
    }

    @Test func accountsPrivacyAndLegacyUpgradeFailClosed() async throws {
        let store = IsolatedCloudStore()
        let a = coordinator(store, account: " Listener "), b = coordinator(store, account: "other")
        try await a.prepare()
        let lease = try await a.acquireLease(for: listen())
        #expect(lease.accountUsername == "listener")
        // Legacy binaries compare this field literally to the bare username.
        #expect(await store.record("global")?["username"] as? String == "aura-coordination-v2:listener")
        do { _ = try await b.acquireLease(for: listen(100)); Issue.record("Account crossed") } catch CloudCoordinationError.accountMismatch {}
        try await a.setPrivateMode(true, effectiveAt: start)
        do { _ = try await a.acquireLease(for: listen(200)); Issue.record("Private submission allowed") } catch CloudCoordinationError.privateMode {}
        let legacyStore = IsolatedCloudStore()
        await legacyStore.seedOldGate()
        let legacyCloud = coordinator(legacyStore)
        try await legacyCloud.prepare()
        do { _ = try await legacyCloud.acquireLease(for: listen()); Issue.record("Unreviewed migration allowed") } catch CloudCoordinationError
            .legacyUpgradeRequired
        {}
    }

    @Test func versionTwoGateWithBareLegacyAccountCannotBypassUpgrade() async throws {
        let store = IsolatedCloudStore(), cloud = coordinator(store)
        try await cloud.prepare()
        try await store.replaceGateAccount("listener")
        do { _ = try await cloud.acquireLease(for: listen()); Issue.record("Unfenced old client account accepted") } catch CloudCoordinationError
            .legacyUpgradeRequired
        {}
    }

    @Test func sameDeviceReentryExpiredLeasesAndStaleCompletionAreBlocked() async throws {
        let store = IsolatedCloudStore(), device = UUID()
        let cloud = coordinator(store, device: device)
        try await cloud.prepare()
        let play = listen(), lease = try await cloud.acquireLease(for: play)
        do { _ = try await cloud.acquireLease(for: play); Issue.record("Reentrant submission allowed") } catch CloudCoordinationError.leaseHeld {}
        let later = coordinator(store, device: device, time: start.addingTimeInterval(121))
        do { _ = try await later.acquireLease(for: play); Issue.record("Unknown outcome retried") } catch CloudCoordinationError.uncertainSubmission {}
        try await cloud.complete(lease, result: .deferred("Definite refusal"))
        let replacement = try await cloud.acquireLease(for: play)
        #expect(replacement.token != lease.token)
        do { try await cloud.complete(lease, result: .accepted(start)); Issue.record("Stale completion accepted") } catch CloudCoordinationError.leaseHeld {}
        try await cloud.complete(replacement, result: .accepted(start))
    }

    @Test func simultaneousDevicesCannotAcquireTwoLeases() async throws {
        let store = IsolatedCloudStore()
        let a = coordinator(store), b = coordinator(store)
        try await a.prepare()
        func acquire(_ coordinator: CloudSubmissionCoordinator, _ play: CanonicalListen) async -> Bool {
            do { _ = try await coordinator.acquireLease(for: play); return true } catch { return false }
        }
        async let first = acquire(a, listen(-1))
        async let second = acquire(b, listen(1, source: "different"))
        let outcomes = await [first, second]
        #expect(outcomes.filter { $0 }.count == 1)
    }

    @Test func failedReceiptSaveDoesNotPermitAutomaticResubmission() async throws {
        let store = IsolatedCloudStore()
        let cloud = coordinator(store)
        try await cloud.prepare()
        let play = listen(), lease = try await cloud.acquireLease(for: play)
        await store.failNextWrite()
        do { try await cloud.complete(lease, result: .accepted(start)); Issue.record("Expected simulated write failure") } catch is CKError {}
        let later = coordinator(store, time: start.addingTimeInterval(121))
        do { _ = try await later.acquireLease(for: play); Issue.record("Accepted play was resubmitted") } catch CloudCoordinationError.uncertainSubmission {}
        // Retrying the receipt, rather than Last.fm, is safe with the same token.
        try await cloud.complete(lease, result: .accepted(start))
        do { _ = try await later.acquireLease(for: play); Issue.record("Receipt ignored") } catch CloudCoordinationError.alreadySubmitted {}
    }

    @Test func missingLegacyMetadataIsNeverTreatedAsReceipt() async throws {
        let store = IsolatedCloudStore(), play = listen(legacy: true)
        let cloud = coordinator(store)
        try await cloud.prepare()
        await store.seedIncomplete(play.id)
        do { _ = try await cloud.acquireLease(for: play); Issue.record("Incomplete receipt accepted") } catch CloudCoordinationError.ambiguousIdentity {}
    }

    @Test func ambiguousMatchesAreReviewedRatherThanMergedIntoFirst() {
        let one = listen(-80), two = listen(80), middle = listen()
        #expect(DefaultEvidenceMerger().merge(middle.evidence[0], into: [one, two]) == .review(nil, .ambiguousDuplicate))
    }
}

// In-memory CAS store: no entitlements, CKContainer, network or live data. It
// returns independent record snapshots so tests cannot mutate stored state.
actor IsolatedCloudStore: CloudRecordStore {
    private var records: [CKRecord.ID: CKRecord] = [:]
    private var failWrite = false
    func failNextWrite() { failWrite = true }
    func prepare(zone: CKRecordZone.ID) {}
    func fetch(_ id: CKRecord.ID) -> CKRecord? { records[id].map(copy) }
    func record(_ name: String) -> CKRecord? { fetch(.init(recordName: name, zoneID: CloudSubmissionCoordinator.zoneID)) }
    func save(_ values: [CKRecord]) throws {
        if failWrite { failWrite = false; throw CKError(.networkFailure) }
        for value in values {
            let stored = records[value.recordID]
            guard stored?["testRevision"] as? Int == value["testRevision"] as? Int else { throw CKError(.serverRecordChanged) }
        }
        for value in values {
            let snapshot = copy(value)
            snapshot["testRevision"] = ((value["testRevision"] as? Int ?? 0) + 1) as CKRecordValue
            records[value.recordID] = snapshot
        }
    }
    func submittedCount() -> Int { records.values.filter { $0["state"] as? String == "submitted" }.count }
    func replaceGateAccount(_ account: String) throws {
        let gate = record("global")!
        gate["username"] = account as CKRecordValue
        try save([gate])
    }
    func seedOldGate() {
        let record = CKRecord(recordType: "SubmissionGate", recordID: .init(recordName: "global", zoneID: CloudSubmissionCoordinator.zoneID));
        records[record.recordID] = record
    }
    func seedIncomplete(_ name: String) {
        let record = CKRecord(recordType: "Listen", recordID: .init(recordName: name, zoneID: CloudSubmissionCoordinator.zoneID));
        records[record.recordID] = record
    }
    func seedLegacy(_ play: CanonicalListen, account: String, submitted: Date) throws {
        let gate = record("global")!
        gate["username"] = ("aura-coordination-v2:" + account) as CKRecordValue
        let record = CKRecord(recordType: "Listen", recordID: .init(recordName: play.id, zoneID: CloudSubmissionCoordinator.zoneID))
        record["title"] = play.canonicalMetadata.title as CKRecordValue
        record["artist"] = play.canonicalMetadata.artist as CKRecordValue
        record["startedAt"] = play.canonicalMetadata.startedAt as CKRecordValue?
        record["state"] = "submitted" as CKRecordValue
        record["submittedAt"] = submitted as CKRecordValue
        try save([gate, record])
    }
    private func copy(_ record: CKRecord) -> CKRecord {
        let result = CKRecord(recordType: record.recordType, recordID: record.recordID)
        for key in record.allKeys() { result[key] = record[key] }
        return result
    }
}
