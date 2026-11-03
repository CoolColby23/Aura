import CryptoKit
import Foundation

public enum MergeDecision: Sendable, Equatable {
    case newListen(String)
    case merge(String)
    case review(String?, ReviewReason)
}

public protocol EvidenceMerger: Sendable {
    func merge(_ evidence: PlaybackEvidence, into candidates: [CanonicalListen]) -> MergeDecision
}

public struct DefaultEvidenceMerger: EvidenceMerger {
    public init() {}

    public func merge(_ evidence: PlaybackEvidence, into candidates: [CanonicalListen]) -> MergeDecision {
        let identity = CanonicalListenIdentity.make(for: evidence)
        let metadataMatches = candidates.filter {
            $0.canonicalMetadata.title.presenceNormalized == evidence.originalMetadata.title.presenceNormalized
                && $0.canonicalMetadata.artist.presenceNormalized == evidence.originalMetadata.artist.presenceNormalized
                && SamePlayWindow.contains($0.canonicalMetadata, evidence.originalMetadata)
        }
        if metadataMatches.count == 1 { return .merge(metadataMatches[0].id) }
        if metadataMatches.count > 1 { return .review(nil, .ambiguousDuplicate) }
        return .newListen(identity)
    }

}

/// Bound the matching tolerance by half a short track so a normal repeat
/// cannot be swallowed by the historical 90-second cross-device window.
public enum SamePlayWindow {
    public static func contains(_ lhs: ScrobbleMetadata, _ rhs: ScrobbleMetadata) -> Bool {
        guard let a = lhs.startedAt, let b = rhs.startedAt else { return false }
        let durations = [lhs.duration, rhs.duration].compactMap { $0 }.filter { $0.isFinite && $0 > 30 }
        let tolerance = min(90, durations.min().map { $0 / 2 } ?? 90)
        return abs(a.timeIntervalSince(b)) <= tolerance
    }
}

public enum CanonicalListenIdentity {
    public static func make(for evidence: PlaybackEvidence) -> String {
        let metadata = evidence.originalMetadata
        let timestamp = (metadata.startedAt ?? evidence.capturedAt).timeIntervalSince1970
        // IDs are local ledger keys, not proof that two devices observed one play.
        // Keep full timestamp precision: distinct repeated plays must never alias.
        let source = evidence.sourceTrackID ?? "\(metadata.artist.presenceNormalized)|\(metadata.title.presenceNormalized)"
        return "v2-" + digest("\(source)|\(metadata.artist.presenceNormalized)|\(metadata.title.presenceNormalized)|\(timestamp)")
    }

    public static func legacy(for evidence: PlaybackEvidence, bucketOffset: Int = 0) -> String {
        let metadata = evidence.originalMetadata
        let bucket = Int((metadata.startedAt ?? evidence.capturedAt).timeIntervalSince1970 / 120) + bucketOffset
        let source = evidence.sourceTrackID ?? "\(metadata.artist.presenceNormalized)|\(metadata.title.presenceNormalized)"
        return digest("\(source)|\(bucket)")
    }

    static func cloudIndex(metadata: ScrobbleMetadata, offset: Int = 0) -> String {
        let bucket = Int(metadata.startedAt!.timeIntervalSince1970 / 120) + offset
        return "index-v2-" + digest("\(metadata.artist.presenceNormalized)|\(metadata.title.presenceNormalized)|\(bucket)")
    }

    private static func digest(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

public enum EvidenceReducer {
    public static func add(_ evidence: PlaybackEvidence, to listen: CanonicalListen) -> CanonicalListen {
        var result = listen
        guard !result.evidence.contains(where: { $0.id == evidence.id }) else { return result }
        // Reconciliation creates a fresh evidence UUID on every scan. Treat
        // the same source and play timestamp as the same event so rescanning
        // cannot inflate a song's scrobble count.
        if evidence.origin == .reconciled,
            result.evidence.contains(where: { prior in
                prior.origin == .reconciled
                    && prior.sourceTrackID == evidence.sourceTrackID
                    && sameTimestamp(prior.originalMetadata.startedAt, evidence.originalMetadata.startedAt)
            })
        {
            return result
        }
        result.evidence.append(evidence)
        let strongest = result.evidence.max {
            if $0.confidence.rank != $1.confidence.rank { return $0.confidence.rank < $1.confidence.rank }
            return ($0.observedPlayTime ?? 0) < ($1.observedPlayTime ?? 0)
        }
        if let strongest { result.canonicalMetadata = strongest.originalMetadata }
        return result
    }

    private static func sameTimestamp(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return abs(lhs.timeIntervalSince(rhs)) < 1
    }
}
