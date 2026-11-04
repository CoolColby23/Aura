import Foundation
import SwiftData
import Testing

@testable import Aura

struct MaintenanceRegressionTests {
    private func track(duration: Double = 40) -> TrackMetadata {
        .init(
            identity: .init(persistentID: "repeat"), title: "Track", artist: "Artist", album: nil,
            duration: duration, source: .localFile, appleMusicURL: nil, artworkReference: nil)
    }

    private func play(at start: TimeInterval) -> PlaybackSession {
        .init(
            id: UUID(), track: track(), startedAt: Date(timeIntervalSince1970: start),
            accumulatedPlayTime: 40, lastPosition: 40, eligibility: .eligible, outcome: .played)
    }

    @Test @MainActor func shortRepeatsInOneMinuteAreQueuedIndependently() throws {
        let store = try PersistenceStore(inMemory: true)
        let first = play(at: 1200), second = play(at: 1240)
        #expect(first.legacyDuplicateKey == second.legacyDuplicateKey)
        #expect(store.enqueue(first) == .accepted)
        #expect(store.enqueue(second) == .accepted)
        #expect(store.enqueue(second) == .duplicate)
        #expect(try store.context.fetchCount(FetchDescriptor<ScrobbleRecord>()) == 2)
    }

    @Test @MainActor func legacyQueueKeysArePreservedWithoutSuppressingRepeat() throws {
        let store = try PersistenceStore(inMemory: true)
        let first = play(at: 1200), second = play(at: 1240)
        let row = ScrobbleRecord(session: first, now: .now)
        row.duplicateKey = first.legacyDuplicateKey
        store.context.insert(row); store.save()
        #expect(store.enqueue(first) == .duplicate)
        #expect(store.enqueue(second) == .accepted)
        #expect(row.duplicateKey == first.legacyDuplicateKey)
    }

    @Test func lateDurationMakesExistingSessionEligible() async throws {
        let tracker = PlaybackSessionTracker(), start = Date(timeIntervalSince1970: 1200)
        _ = await tracker.ingest(.init(track: track(duration: 0), state: .playing, position: 0, observedAt: start, confidence: .high))
        let original = try #require(await tracker.active)
        _ = await tracker.ingest(.init(track: track(), state: .playing, position: 25, observedAt: start.addingTimeInterval(25), confidence: .high))
        let updated = try #require(await tracker.active)
        #expect(updated.id == original.id)
        #expect(updated.track.duration == 40)
        #expect(updated.eligibility == .eligible)
    }

    @Test @MainActor func removingQueuedRowDuringEarlierRequestPreventsItsSubmission() async throws {
        let store = try PersistenceStore(inMemory: true)
        store.enqueue(play(at: 1200)); store.enqueue(play(at: 1240))
        let rows = try store.context.fetch(FetchDescriptor<ScrobbleRecord>(sortBy: [SortDescriptor(\.startedAt)]))
        let client = MaintenanceSubmitter(), queue = ScrobbleQueue(store: store, client: client)
        async let drain: Void = queue.process()
        await client.waitUntilStarted()
        queue.remove(id: rows[1].id)
        await client.release()
        await drain
        #expect(await client.count == 1)
        #expect(try store.context.fetchCount(FetchDescriptor<ScrobbleRecord>()) == 1)
    }
}

private actor MaintenanceSubmitter: ScrobbleSubmitting {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var count = 0
    func scrobble(title: String, artist: String, album: String?, duration: Double, startedAt: Date) async throws {
        count += 1
        started?.resume(); started = nil
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilStarted() async {
        if count > 0 { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}
