import CloudKit
import Foundation

public enum CloudCoordinationError: LocalizedError {
    case unavailable, privateMode, accountMismatch, leaseHeld, ambiguousIdentity, uncertainSubmission, unauthorized, legacyUpgradeRequired
    case alreadySubmitted(Date)
    public var errorDescription: String? {
        switch self {
        case .unavailable: "Cloud coordination is unavailable. The scrobble remains queued."
        case .privateMode: "Private Mode prevents submission."
        case .accountMismatch: "Mac and iPhone must use the same Last.fm account."
        case .leaseHeld: "Another submission owns this listen."
        case .ambiguousIdentity: "Legacy or conflicting listen evidence needs reconciliation before submission."
        case .uncertainSubmission: "A previous submission has an unknown outcome. Check Last.fm before retrying."
        case .legacyUpgradeRequired: "Existing cloud history needs a reviewed compatibility upgrade before submission."
        case .unauthorized: "Connect Last.fm before submitting."
        case .alreadySubmitted: "This listen was already submitted from another device."
        }
    }
}

// The same coordinator is exercised by isolated macOS tests. Production uses only
// the private CloudKit adapter; tests never construct a CKContainer.
protocol CloudRecordStore: Sendable {
    func prepare(zone: CKRecordZone.ID) async throws
    func fetch(_ id: CKRecord.ID) async throws -> CKRecord?
    func save(_ records: [CKRecord]) async throws
}

private struct PrivateCloudStore: CloudRecordStore {
    let database: CKDatabase
    func prepare(zone: CKRecordZone.ID) async throws { _ = try await database.save(CKRecordZone(zoneID: zone)) }
    func fetch(_ id: CKRecord.ID) async throws -> CKRecord? {
        do { return try await database.record(for: id) } catch let error as CKError where error.code == .unknownItem { return nil }
    }
    func save(_ records: [CKRecord]) async throws {
        let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        for value in result.saveResults.values { _ = try value.get() }
    }
}

public actor CloudSubmissionCoordinator: SubmissionCoordinator {
    static let zoneID = CKRecordZone.ID(zoneName: "Aura", ownerName: CKCurrentUserDefaultName)
    private let database: (any CloudRecordStore)?
    private let deviceID: UUID
    private let username: @Sendable () async -> String?
    private let localOnly: Bool
    private let now: @Sendable () -> Date

    public init(containerIdentifier: String?, deviceID: UUID, localOnly: Bool = false, username: @escaping @Sendable () async -> String?) {
        database = containerIdentifier.map { PrivateCloudStore(database: CKContainer(identifier: $0).privateCloudDatabase) }
        self.deviceID = deviceID; self.localOnly = localOnly; self.username = username; now = { Date() }
    }

    init(database: any CloudRecordStore, deviceID: UUID, now: @escaping @Sendable () -> Date = { Date() }, username: @escaping @Sendable () async -> String?) {
        self.database = database; self.deviceID = deviceID; self.now = now; self.username = username; localOnly = false
    }

    public func prepare() async throws {
        guard let database else { if localOnly { return }; throw CloudCoordinationError.unavailable }
        try await database.prepare(zone: Self.zoneID)
        if try await database.fetch(id("global")) == nil {
            let gate = CKRecord(recordType: "SubmissionGate", recordID: id("global"))
            gate["coordinationVersion"] = 2 as CKRecordValue
            gate["generation"] = 1 as CKRecordValue; gate["privateMode"] = false as CKRecordValue
            try await database.save([gate])
        }
    }

    public func acquireLease(for local: CanonicalListen) async throws -> SubmissionLease {
        guard let rawAccount = await username() else { throw CloudCoordinationError.unauthorized }
        let account = rawAccount.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !account.isEmpty else { throw CloudCoordinationError.unauthorized }
        guard let date = local.canonicalMetadata.startedAt, date.timeIntervalSince1970.isFinite, abs(date.timeIntervalSince1970) < 1e12 else {
            throw CloudCoordinationError.ambiguousIdentity
        }
        guard let database else {
            if localOnly {
                return SubmissionLease(
                    listenID: local.id, ownerDeviceID: deviceID, acquiredAt: now(), expiresAt: now().addingTimeInterval(120), accountUsername: account)
            }
            throw CloudCoordinationError.unavailable
        }
        guard let gate = try await database.fetch(id("global")) else { throw CloudCoordinationError.unavailable }
        guard (gate["coordinationVersion"] as? NSNumber)?.intValue == 2 else { throw CloudCoordinationError.legacyUpgradeRequired }
        if (gate["privateMode"] as? NSNumber)?.boolValue == true { throw CloudCoordinationError.privateMode }
        let rawSelected = (gate["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Old binaries require username == the Last.fm username. A versioned
        // value fences their lease acquisition after an explicit v2 activation.
        let prefix = "aura-coordination-v2:"
        if let rawSelected, !rawSelected.isEmpty, !rawSelected.hasPrefix(prefix) { throw CloudCoordinationError.legacyUpgradeRequired }
        let selected = rawSelected.map { String($0.dropFirst(prefix.count)) }
        if let selected, !selected.isEmpty, selected != account { throw CloudCoordinationError.accountMismatch }

        // Query-free, bounded lookup: adjacent two-minute indices cover the
        // merger's 90-second window even across a bucket boundary. Catalog IDs
        // and device IDs deliberately do not partition cross-device lookup.
        var indices: [CKRecord] = []
        var candidateIDs: Set<String> = [local.id]
        for offset in -1...1 {
            let indexID = id(CanonicalListenIdentity.cloudIndex(metadata: local.canonicalMetadata, offset: offset))
            let index = try await database.fetch(indexID) ?? CKRecord(recordType: "Listen", recordID: indexID)
            indices.append(index)
            candidateIDs.formUnion(index["listenIDs"] as? [String] ?? [])
            for evidence in local.evidence {
                let timestamp = (evidence.originalMetadata.startedAt ?? evidence.capturedAt).timeIntervalSince1970
                guard timestamp.isFinite, abs(timestamp) < 1e12 else { throw CloudCoordinationError.ambiguousIdentity }
                candidateIDs.insert(CanonicalListenIdentity.legacy(for: evidence, bucketOffset: offset))
            }
        }
        var matches: [CKRecord] = []
        for candidateID in candidateIDs.sorted() {
            guard let record = try await database.fetch(id(candidateID)) else { continue }
            guard let startedAt = record["startedAt"] as? Date,
                let title = record["title"] as? String, let artist = record["artist"] as? String
            else { throw CloudCoordinationError.ambiguousIdentity }
            if let owner = record["username"] as? String, owner.lowercased() != account { throw CloudCoordinationError.accountMismatch }
            // An unscoped legacy receipt is safe only if the existing gate
            // already establishes which Last.fm account it belongs to.
            if record["username"] == nil && (selected == nil || selected == "") { throw CloudCoordinationError.ambiguousIdentity }
            guard let state = record["state"] as? String, ListenState(rawValue: state) != nil else { throw CloudCoordinationError.ambiguousIdentity }
            if title.presenceNormalized == local.canonicalMetadata.title.presenceNormalized,
                artist.presenceNormalized == local.canonicalMetadata.artist.presenceNormalized,
                SamePlayWindow.contains(
                    ScrobbleMetadata(title: title, artist: artist, duration: (record["duration"] as? NSNumber)?.doubleValue, startedAt: startedAt),
                    local.canonicalMetadata)
            {
                matches.append(record)
            } else if candidateID == local.id {
                // Existing ledgers can contain duplicate legacy IDs. Never
                // choose a receipt using an ID that disagrees with the play.
                if !local.id.hasPrefix("v2-") { continue }
                throw CloudCoordinationError.ambiguousIdentity
            }
        }
        guard matches.count <= 1 else { throw CloudCoordinationError.ambiguousIdentity }
        let record: CKRecord
        if let match = matches.first {
            record = match
        } else {
            // Never reuse a legacy ledger key for a different play.
            let cloudID = "play-" + CanonicalListenIdentity.cloudIndex(metadata: local.canonicalMetadata) + "-" + String(date.timeIntervalSince1970)
            record = CKRecord(recordType: "Listen", recordID: id(cloudID))
            record["title"] = local.canonicalMetadata.title as CKRecordValue
            record["artist"] = local.canonicalMetadata.artist as CKRecordValue
            record["startedAt"] = date as CKRecordValue
            record["duration"] = local.canonicalMetadata.duration as CKRecordValue?
        }
        if record["state"] as? String == ListenState.submitted.rawValue {
            guard let submitted = record["submittedAt"] as? Date else { throw CloudCoordinationError.ambiguousIdentity }
            throw CloudCoordinationError.alreadySubmitted(submitted)
        }
        if let expiry = record["leaseExpiresAt"] as? Date, expiry > now() { throw CloudCoordinationError.leaseHeld }
        // Last.fm has no idempotency key. An expired in-flight lease might have
        // been accepted before a crash, so stealing it can duplicate a scrobble.
        if record["state"] as? String == ListenState.submitting.rawValue { throw CloudCoordinationError.uncertainSubmission }
        let lease = SubmissionLease(
            listenID: record.recordID.recordName, ownerDeviceID: deviceID, acquiredAt: now(), expiresAt: now().addingTimeInterval(120), accountUsername: account
        )
        record["username"] = account as CKRecordValue
        record["leaseOwner"] = deviceID.uuidString as CKRecordValue
        record["leaseToken"] = lease.token as CKRecordValue?
        record["leaseExpiresAt"] = lease.expiresAt as CKRecordValue
        record["state"] = ListenState.submitting.rawValue as CKRecordValue
        let index = indices[1]
        var links = Set(index["listenIDs"] as? [String] ?? [])
        links.insert(record.recordID.recordName)
        index["listenIDs"] = links.sorted() as CKRecordValue
        gate["username"] = ("aura-coordination-v2:" + account) as CKRecordValue
        gate["generation"] = ((gate["generation"] as? NSNumber)?.intValue ?? 0) + 1 as CKRecordValue
        // Both contenders read the gate before resolving. Atomic CAS on it
        // prevents two devices from creating different records for one play.
        try await database.save([gate, index, record])
        return lease
    }

    public func complete(_ lease: SubmissionLease, result: SubmissionResult) async throws {
        guard let database else { return }
        guard let record = try await database.fetch(id(lease.listenID)),
            record["leaseOwner"] as? String == deviceID.uuidString,
            let token = lease.token, record["leaseToken"] as? String == token,
            record["username"] as? String == lease.accountUsername
        else { throw CloudCoordinationError.leaseHeld }
        switch result {
        case .accepted(let date): record["state"] = ListenState.submitted.rawValue as CKRecordValue; record["submittedAt"] = date as CKRecordValue
        case .rejected(let message): record["state"] = ListenState.failed.rawValue as CKRecordValue; record["lastError"] = message as CKRecordValue
        case .deferred(let message): record["state"] = ListenState.queued.rawValue as CKRecordValue; record["lastError"] = message as CKRecordValue
        }
        record["leaseOwner"] = nil; record["leaseToken"] = nil; record["leaseExpiresAt"] = nil
        try await database.save([record])
    }

    public func setPrivateMode(_ enabled: Bool, effectiveAt: Date) async throws {
        guard let database else { if localOnly { return }; throw CloudCoordinationError.unavailable }
        guard let gate = try await database.fetch(id("global")) else { throw CloudCoordinationError.unavailable }
        gate["privateMode"] = enabled as CKRecordValue; gate["privateModeEffectiveAt"] = effectiveAt as CKRecordValue
        gate["generation"] = ((gate["generation"] as? NSNumber)?.intValue ?? 0) + 1 as CKRecordValue
        try await database.save([gate])
    }

    private func id(_ name: String) -> CKRecord.ID { CKRecord.ID(recordName: name, zoneID: Self.zoneID) }
}
