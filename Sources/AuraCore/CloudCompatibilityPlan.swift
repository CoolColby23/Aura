import CloudKit
import Foundation

/// Offline preparation only. No database reference, network calls or startup
/// migration. The caller must supply a complete, quiesced and reconciled export.
/// A plan is not evidence that the export is complete or Last.fm accepted it.
struct CloudCompatibilityPlan {
    enum Invalid: Error { case gate, account, record, unresolved, index }
    let indices: [CKRecord]
    let pausedGate: CKRecord

    init(gate: CKRecord, records: [CKRecord], account rawAccount: String) throws {
        let account = rawAccount.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !account.isEmpty else { throw Invalid.account }
        guard gate.recordType == "SubmissionGate", gate.recordID.recordName == "global",
            gate.recordID.zoneID == CloudSubmissionCoordinator.zoneID,
            let generation = gate["generation"] as? Int64, generation >= 0, generation < Int64.max,
            gate["coordinationVersion"] == nil || (gate["coordinationVersion"] as? NSNumber)?.intValue == 2
        else { throw Invalid.gate }
        let selected = (gate["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard selected == account || selected == "aura-coordination-v2:" + account else { throw Invalid.account }
        var links: [String: Set<String>] = [:]
        var existing: [String: CKRecord] = [:]
        var seen: Set<String> = []
        for record in records {
            guard record.recordType == "Listen", record.recordID.zoneID == gate.recordID.zoneID,
                seen.insert(record.recordID.recordName).inserted
            else { throw Invalid.record }
            if record.recordID.recordName.hasPrefix("index-v2-") {
                guard let ids = record["listenIDs"] as? [String] else { throw Invalid.index }
                links[record.recordID.recordName] = Set(ids)
                existing[record.recordID.recordName] = record
            }
        }
        let plays = records.filter { !$0.recordID.recordName.hasPrefix("index-v2-") }
        for record in plays {
            guard let owner = record["username"] as? String,
                owner.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == account
            else { throw Invalid.account }
            guard let title = record["title"] as? String, !title.presenceNormalized.isEmpty,
                let artist = record["artist"] as? String, !artist.presenceNormalized.isEmpty,
                let date = record["startedAt"] as? Date,
                date.timeIntervalSince1970.isFinite, abs(date.timeIntervalSince1970) < 1e12
            else { throw Invalid.record }
            guard let state = record["state"] as? String, ["queued", "failed", "submitted"].contains(state),
                record["leaseOwner"] == nil, record["leaseToken"] == nil, record["leaseExpiresAt"] == nil,
                (state != "submitted" || record["submittedAt"] is Date),
                (state == "submitted" || record["submittedAt"] == nil)
            else { throw Invalid.unresolved }
            let metadata = ScrobbleMetadata(title: title, artist: artist, duration: record["duration"] as? Double, startedAt: date)
            links[CanonicalListenIdentity.cloudIndex(metadata: metadata), default: []].insert(record.recordID.recordName)
        }
        let ids = Set(plays.map { $0.recordID.recordName })
        guard links.values.allSatisfy({ $0.isSubset(of: ids) }) else { throw Invalid.index }
        indices = try links.keys.sorted().map { name in
            let index = try existing[name].map(Self.copy) ?? CKRecord(recordType: "Listen", recordID: .init(recordName: name, zoneID: gate.recordID.zoneID))
            index["listenIDs"] = links[name]!.sorted() as CKRecordValue
            return index
        }
        pausedGate = try Self.copy(gate)
        pausedGate["coordinationVersion"] = 2 as CKRecordValue
        pausedGate["username"] = ("aura-coordination-v2:" + account) as CKRecordValue
        pausedGate["privateMode"] = true as CKRecordValue
        pausedGate["generation"] = (generation + 1) as CKRecordValue
    }

    private static func copy(_ record: CKRecord) throws -> CKRecord {
        // Preserve CloudKit system fields/change tags for a later reviewed CAS.
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        let decoder = try NSKeyedUnarchiver(forReadingFrom: coder.encodedData)
        decoder.requiresSecureCoding = true
        guard let result = CKRecord(coder: decoder) else { throw Invalid.record }
        decoder.finishDecoding()
        for key in record.allKeys() { result[key] = record[key] }
        return result
    }
}
