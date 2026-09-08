import AuraCore
import Foundation
import MediaPlayer
import MusicKit

actor AppleMusicEvidenceSource: PlaybackEvidenceSource {
    /// Bounds a history scan so a long or unexpectedly repeating page sequence
    /// cannot keep the import spinning against the network.
    private static let maximumHistoryPages = 20
    /// Apple's recently played tracks endpoint rejects limits above 30.
    private static let historyPageLimit = 30

    private let player = MPMusicPlayerController.systemMusicPlayer
    private let deviceID: UUID
    private var lastItemID: String?
    private var accumulated: TimeInterval = 0
    private var lastPosition: TimeInterval?
    private var lastObservedAt: Date?

    init(deviceID: UUID) { self.deviceID = deviceID }

    func requestAuthorization() async -> MusicAuthorization.Status { await MusicAuthorization.request() }
    func establishBaseline() async throws -> CaptureBaseline { CaptureBaseline() }

    func currentEvidence() async -> PlaybackEvidence? {
        guard let item = player.nowPlayingItem else { reset(); return nil }
        let now = Date(); let position = max(0, player.currentPlaybackTime)
        let itemID = item.playbackStoreID.isEmpty ? String(item.persistentID) : item.playbackStoreID
        if itemID != lastItemID { accumulated = 0; lastPosition = nil; lastObservedAt = nil; lastItemID = itemID }
        if player.playbackState == .playing, let priorPosition = lastPosition, let priorDate = lastObservedAt {
            let wall = max(0, now.timeIntervalSince(priorDate)); let delta = position - priorPosition
            if delta >= -2, delta <= wall + 4 { accumulated += min(wall, max(0, delta + 1)) }
        }
        lastPosition = position; lastObservedAt = now
        let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = item.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        let duration = item.playbackDuration > 0 ? item.playbackDuration : nil
        let startedAt = now.addingTimeInterval(-position)
        return PlaybackEvidence(
            deviceID: deviceID, platform: item.playbackStoreID.isEmpty ? .localMusic : .appleMusic,
            sourceTrackID: itemID, metadata: .init(title: title, artist: artist, album: item.albumTitle, duration: duration, startedAt: startedAt),
            observedPlayTime: accumulated, origin: .observed, confidence: .strong, capturedAt: now
        )
    }

    func reconcile(since cursor: ReconciliationCursor) async throws -> ReconciliationResult {
        let evidence: [PlaybackEvidence]
        do {
            evidence = try await musicKitHistory(since: cursor.lastCheckedAt)
        } catch {
            // Automatic MusicKit tokens are unavailable for some locally
            // signed builds. The media library still exposes the same last
            // played dates that Last.fm-style history scanning needs.
            evidence = mediaLibraryHistory(since: cursor.lastCheckedAt)
            if evidence.isEmpty { throw error }
        }
        return ReconciliationResult(evidence: evidence, cursor: .init(lastCheckedAt: .now))
    }

    private func musicKitHistory(since date: Date) async throws -> [PlaybackEvidence] {
        var request = MusicRecentlyPlayedRequest<Song>()
        request.limit = Self.historyPageLimit
        let response = try await request.response()
        // Paginate from the most recent batch, never from the accumulated
        // results: the paging token belongs to the batch MusicKit returned.
        var batch = response.items
        var songs = Array(batch)
        var pagesFetched = 1
        while batch.hasNextBatch, pagesFetched < Self.maximumHistoryPages {
            guard let next = try await batch.nextBatch(limit: Self.historyPageLimit), !next.isEmpty else { break }
            songs += next
            batch = next
            pagesFetched += 1
        }
        return songs.compactMap { song in
            guard let played = song.lastPlayedDate, played > date else { return nil }
            return PlaybackEvidence(
                deviceID: deviceID, sourceTrackID: song.id.rawValue,
                metadata: .init(
                    title: song.title, artist: song.artistName, album: song.albumTitle,
                    duration: song.duration, startedAt: played),
                observedPlayTime: nil, origin: .reconciled, confidence: .probable, capturedAt: .now
            )
        }
    }

    private func mediaLibraryHistory(since date: Date) -> [PlaybackEvidence] {
        let items = MPMediaQuery.songs().items ?? []
        let evidence: [PlaybackEvidence] = items.flatMap {
            mediaLibraryEvidence(from: $0, since: date)
        }
        return evidence.sorted(by: { lhs, rhs in
            (lhs.originalMetadata.startedAt ?? .distantPast)
                > (rhs.originalMetadata.startedAt ?? .distantPast)
        })
    }

    private func mediaLibraryEvidence(from item: MPMediaItem, since date: Date) -> [PlaybackEvidence] {
        guard let played = item.lastPlayedDate, played > date else { return [] }
        guard let rawTitle = item.title, let rawArtist = item.artist else { return [] }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = rawArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty else { return [] }

        let storeID = item.playbackStoreID
        let sourceID: String
        let platform: CompanionPlatform
        if storeID.isEmpty {
            sourceID = item.persistentID.description
            platform = .localMusic
        } else {
            sourceID = storeID
            platform = .appleMusic
        }
        let duration: TimeInterval? = item.playbackDuration > 0 ? item.playbackDuration : nil
        // Last.fm's batch scanner represents the media item's play count as
        // repeated scrobbles. Space inferred timestamps far enough apart that
        // the merge engine keeps each play distinct while the newest play
        // remains anchored to Apple's last-played date.
        let dates = Self.inferredPlayDates(
            lastPlayedAt: played, playCount: item.playCount,
            duration: duration, since: date)
        return dates.map { startedAt in
            let metadata = ScrobbleMetadata(
                title: title, artist: artist, album: item.albumTitle,
                duration: duration, startedAt: startedAt)
            return PlaybackEvidence(
                deviceID: deviceID, platform: platform, sourceTrackID: sourceID, metadata: metadata,
                observedPlayTime: nil, origin: .reconciled, confidence: .probable, capturedAt: .now
            )
        }
    }

    static func inferredPlayDates(
        lastPlayedAt: Date, playCount: Int, duration: TimeInterval?, since date: Date
    ) -> [Date] {
        let spacing = max(120, duration ?? 180)
        return (0..<max(1, playCount)).compactMap { index in
            let startedAt = lastPlayedAt.addingTimeInterval(-Double(index) * spacing)
            return startedAt > date ? startedAt : nil
        }
    }

    func beginNotifications(_ action: @escaping @Sendable () -> Void) {
        player.beginGeneratingPlaybackNotifications()
        NotificationCenter.default.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player, queue: .main) { _ in action() }
        NotificationCenter.default.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange, object: player, queue: .main) { _ in action() }
    }

    private func reset() { lastItemID = nil; accumulated = 0; lastPosition = nil; lastObservedAt = nil }
}
