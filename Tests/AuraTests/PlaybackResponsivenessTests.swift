import AppKit
import Foundation
import Testing

@testable import Aura

@Suite("Playback responsiveness")
struct PlaybackResponsivenessTests {
    @Test @MainActor func stalledCoverDoesNotDelayNextTrackOrOverwriteItsArtwork() async throws {
        let defaultsName = "AuraTests.responsiveness.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let preferences = Preferences(defaults: defaults)
        preferences.enabledPlaybackProviders = [.spotify]
        preferences.discordEnabled = false
        preferences.lastFMEnabled = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stalled = StalledCoverRequest()
        let oldURL = try #require(URL(string: "https://player.example/old-cover.png"))
        let oldTrack = track("old", artwork: .remote(oldURL))
        let newTrack = track("new", artwork: nil)
        let provider = SwitchingPlaybackProvider(track: oldTrack)
        let pollingClock = ClosureAppClock(
            now: { Date() },
            sleep: { _ in
                try await Task.sleep(for: .milliseconds(10))
            })
        let monitor = PlaybackMonitor(credentials: CredentialStore(), clock: pollingClock, providers: [.spotify: provider])
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let imageData = try #require(bitmap.representation(using: .png, properties: [:]))
        let artwork = ArtworkService(
            directory: directory,
            fetch: { request in
                let url = try #require(request.url)
                let body: Data
                if url == oldURL {
                    // Deliberately ignore cancellation until released: some transports
                    // finish an old request after the player has already moved on.
                    await stalled.wait()
                    body = imageData
                } else {
                    body = Data(#"{"results":[]}"#.utf8)
                }
                return (body, try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
            })
        let model = AppModel(
            store: try PersistenceStore(inMemory: true), preferences: preferences,
            notifications: NotificationCoordinator(delivery: ResponsivenessNotificationDelivery()),
            playbackMonitor: monitor, artworkService: artwork
        )
        defer {
            model.shutdown()
            Task { await stalled.release() }
        }
        model.start()
        var requestStarted = false
        for _ in 0..<100 {
            if await stalled.started { requestStarted = true; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(requestStarted)
        await provider.setTrack(newTrack)
        var switchedBeforeCoverFinished = false
        for _ in 0..<50 {
            if model.activeSession?.track.identity == newTrack.identity {
                switchedBeforeCoverFinished = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(switchedBeforeCoverFinished)
        #expect(model.snapshot.track?.identity == newTrack.identity)
        #expect(model.artworkData == nil)
        await stalled.release()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.snapshot.track?.identity == newTrack.identity)
        #expect(model.artworkData == nil)
        #expect(model.discordArtworkURL == nil)
    }

    private func track(_ id: String, artwork: ArtworkReference?) -> TrackMetadata {
        TrackMetadata(
            identity: .init(persistentID: id), title: id, artist: "Artist", album: "Album",
            duration: 180, source: .localFile, appleMusicURL: nil,
            artworkReference: artwork, platform: .spotify
        )
    }
}

private actor SwitchingPlaybackProvider: PlaybackProvider {
    let id = PlaybackProviderID.spotify
    private var track: TrackMetadata
    init(track: TrackMetadata) { self.track = track }
    func setTrack(_ track: TrackMetadata) { self.track = track }
    func snapshot() async -> ProviderSnapshot {
        let now = Date()
        return ProviderSnapshot(
            provider: id,
            playback: PlaybackSnapshot(track: track, state: .playing, position: 1, observedAt: now, confidence: .high),
            health: .available, observedAt: now
        )
    }
}

private actor StalledCoverRequest {
    private(set) var started = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        started = true
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class ResponsivenessNotificationDelivery: NotificationDelivering {
    func requestAuthorization() async -> Bool { false }
    func deliver(identifier: String, title: String, body: String, section: DashboardSection) async {}
}
