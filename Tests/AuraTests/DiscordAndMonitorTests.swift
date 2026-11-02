import Foundation
import SwiftData
import Testing

@testable import Aura

@Suite("Discord customization")
struct DiscordCustomizationTests {
    @Test @MainActor func factoryBuildsCountdownImagesHoverTextAndActivityStyle() throws {
        let defaults = try #require(UserDefaults(suiteName: "AuraTests.discord-customization.\(UUID().uuidString)"))
        let preferences = Preferences(defaults: defaults)
        preferences.discordActivityType = .watching
        preferences.discordActivityName = "On {platform}"
        preferences.discordLineOne = .custom
        preferences.discordCustomLineOne = "{title} • {position}/{duration}"
        preferences.discordLineTwo = .custom
        preferences.discordCustomLineTwo = "{artist} — {album}"
        preferences.discordTimerStyle = .remaining
        preferences.discordLargeImage = .playbackPlatform
        preferences.discordSmallImage = .aura
        preferences.discordLargeImageText = "{album} on {platform}"
        preferences.discordSmallImageText = "Shared by Aura"

        let now = Date(timeIntervalSince1970: 2_000)
        let track = TrackMetadata(
            identity: .init(persistentID: "discord-custom"), title: "Midnight Drive",
            artist: "The Satellites", album: "Afterglow", duration: 224,
            source: .appleMusicCatalog, appleMusicURL: URL(string: "https://example.com/listen"),
            artworkReference: nil, platform: .spotify
        )
        let session = PlaybackSession(
            id: UUID(), track: track, startedAt: now.addingTimeInterval(-82),
            accumulatedPlayTime: 82, lastPosition: 82, eligibility: .listening, outcome: .active
        )
        let snapshot = PlaybackSnapshot(
            track: track, state: .playing, position: 82, observedAt: now, confidence: .high
        )

        let presence = DiscordPresenceFactory.make(
            session: session, snapshot: snapshot, preferences: preferences,
            artworkURL: URL(string: "https://example.com/art.jpg"), now: now
        )
        #expect(presence.title == "Midnight Drive • 1:22/3:44")
        #expect(presence.state == "The Satellites — Afterglow")
        #expect(presence.activityName == "On Spotify")
        #expect(presence.startedAt == nil)
        #expect(presence.endsAt == now.addingTimeInterval(142))

        let payload = DiscordPresenceClient.activityPayload(for: presence)
        #expect(payload["type"] as? Int == 3)
        #expect(payload["name"] as? String == "On Spotify")
        let assets = try #require(payload["assets"] as? [String: String])
        #expect(assets["large_image"] == PlaybackPlatform.spotify.discordSmallImageURL)
        #expect(assets["large_text"] == "Afterglow on Spotify")
        #expect(assets["small_text"] == "Shared by Aura")
        let timestamps = try #require(payload["timestamps"] as? [String: Int])
        #expect(timestamps["start"] == nil)
        #expect(timestamps["end"] == Int(2_142.0 * 1_000))
    }

    @Test @MainActor func pausedPresenceUsesPausedTemplateAndNeverShowsTimer() throws {
        let defaults = try #require(UserDefaults(suiteName: "AuraTests.discord-paused.\(UUID().uuidString)"))
        let preferences = Preferences(defaults: defaults)
        preferences.discordPausedText = "{state} at {position}"
        preferences.discordTimerStyle = .elapsed
        let track = TrackMetadata(
            identity: .init(persistentID: "paused"), title: "Track", artist: "Artist",
            album: nil, duration: 180, source: .appleMusicCatalog,
            appleMusicURL: nil, artworkReference: nil
        )
        let session = PlaybackSession(
            id: UUID(), track: track, startedAt: .now, accumulatedPlayTime: 45,
            lastPosition: 45, eligibility: .listening, outcome: .active
        )
        let snapshot = PlaybackSnapshot(track: track, state: .paused, position: 45, observedAt: .now, confidence: .high)
        let presence = DiscordPresenceFactory.make(
            session: session, snapshot: snapshot, preferences: preferences, artworkURL: nil, now: .now
        )
        #expect(presence.state == "Paused at 0:45 · 3:00")
        #expect(presence.startedAt == nil)
        #expect(presence.endsAt == nil)
    }
    @Test @MainActor func progressTracksDurationPauseSeekAndResume() throws {
        let defaults = try #require(UserDefaults(suiteName: "AuraTests.discord-progress.\(UUID())"))
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.discordTimerStyle == .progress)
        #expect(preferences.discordSharePaused)
        let now = Date(timeIntervalSince1970: 2_000)
        let track = TrackMetadata(
            identity: .init(persistentID: "progress"), title: "Track", artist: "Artist",
            album: "Album", duration: 224, source: .radioStream,
            appleMusicURL: nil, artworkReference: nil
        )
        #expect(track.supportsFiniteProgress)
        let session = PlaybackSession(
            id: UUID(), track: track, startedAt: now.addingTimeInterval(-82), accumulatedPlayTime: 82,
            lastPosition: 82, eligibility: .listening, outcome: .active
        )
        func presence(_ state: PlaybackState, position: TimeInterval, date: Date) -> DiscordPresence {
            DiscordPresenceFactory.make(
                session: session,
                snapshot: PlaybackSnapshot(track: track, state: state, position: position, observedAt: date, confidence: .high),
                preferences: preferences, artworkURL: nil, now: date
            )
        }
        let playing = presence(.playing, position: 82, date: now)
        #expect(playing.state == "Artist • Album · 3:44")
        #expect(playing.startedAt == now.addingTimeInterval(-82))
        #expect(playing.endsAt == now.addingTimeInterval(142))
        let timestamps = try #require(DiscordPresenceClient.activityPayload(for: playing)["timestamps"] as? [String: Int])
        #expect(timestamps["end"]! - timestamps["start"]! == 224_000)

        let paused = presence(.paused, position: 82, date: now)
        #expect(paused.state == "Paused • Artist · 1:22 / 3:44")
        #expect(paused.smallImageText == "Paused on Apple Music")
        #expect(paused.title == playing.title)
        #expect(paused.artworkURL == playing.artworkURL)
        #expect(DiscordPresenceClient.activityPayload(for: paused)["timestamps"] == nil)
        #expect(presence(.paused, position: 82, date: now.addingTimeInterval(60)) == paused)

        let resumed = presence(.playing, position: 100, date: now.addingTimeInterval(60))
        #expect(resumed.startedAt == now.addingTimeInterval(-40))
        #expect(resumed.endsAt == now.addingTimeInterval(184))
        #expect(resumed.smallImageText == "Playing on Apple Music")
        let seekPastEnd = presence(.paused, position: 300, date: now)
        #expect(seekPastEnd.state == "Paused • Artist · 3:44 / 3:44")

        preferences.discordPausedText = "{state} • {position}/{duration}"
        #expect(presence(.paused, position: 82, date: now).state == "Paused • 1:22/3:44")
        preferences.discordTimerStyle = .hidden
        preferences.discordPausedText = "Paused • {artist}"
        let hidden = presence(.paused, position: 82, date: now)
        #expect(hidden.state == "Paused • Artist")
        #expect(presence(.playing, position: 82, date: now).state == "Artist • Album")
    }

    @Test func normalPlaybackDoesNotFloodDiscordButChangesAndSeeksPublish() {
        let start = Date(timeIntervalSince1970: 2_000)
        func presence(title: String = "Track", drift: TimeInterval = 0, paused: Bool = false, artwork: URL? = nil) -> DiscordPresence {
            DiscordPresence(
                title: title, state: paused ? "Paused • Artist · 1:22 / 3:00" : "Artist · 3:00",
                startedAt: paused ? nil : start.addingTimeInterval(drift),
                endsAt: paused ? nil : start.addingTimeInterval(180 + drift),
                appleMusicURL: nil, artworkURL: artwork, buttonLabel: "Listen"
            )
        }
        let initial = presence()
        #expect(!DiscordPresenceClient.shouldPublish(initial, after: initial))
        #expect(!DiscordPresenceClient.shouldPublish(presence(drift: 0.7), after: initial))
        #expect(DiscordPresenceClient.shouldPublish(presence(drift: 10), after: initial))
        #expect(DiscordPresenceClient.shouldPublish(presence(title: "Next Track"), after: initial))
        #expect(DiscordPresenceClient.shouldPublish(presence(paused: true), after: initial))
        #expect(DiscordPresenceClient.shouldPublish(initial, after: presence(paused: true)))
        #expect(DiscordPresenceClient.shouldPublish(presence(artwork: URL(string: "https://example.com/cover.png")), after: initial))
    }

    @Test func durationLabelsMatchDiscordProgressRounding() {
        #expect(DiscordTemplate.render("{position} / {duration}", title: "", artist: "", album: "", platform: .appleMusic, position: 82.8, duration: 230.9) == "1:22 / 3:50")
        #expect(DiscordTemplate.render("{position}", title: "", artist: "", album: "", platform: .appleMusic, position: -1e100) == "0:00")
    }

    @Test @MainActor func unknownAndStreamDurationsDoNotShowFakeProgress() throws {
        let defaults = try #require(UserDefaults(suiteName: "AuraTests.discord-stream.\(UUID())"))
        let preferences = Preferences(defaults: defaults)
        for (duration, source) in [(0.0, TrackSource.localFile), (0.0, .radioStream), (180.0, .unsupportedStream), (Double.infinity, .localFile)] {
            let track = TrackMetadata(
                identity: .init(persistentID: "stream"), title: "Track", artist: "Artist",
                album: nil, duration: duration, source: source, appleMusicURL: nil, artworkReference: nil
            )
            let session = PlaybackSession(
                id: UUID(), track: track, startedAt: .now, accumulatedPlayTime: 82,
                lastPosition: 82, eligibility: .listening, outcome: .active
            )
            let presence = DiscordPresenceFactory.make(
                session: session,
                snapshot: PlaybackSnapshot(track: track, state: .playing, position: .nan, observedAt: .now, confidence: .high),
                preferences: preferences, artworkURL: nil, now: .now
            )
            #expect(presence.state == "Artist")
            #expect(presence.startedAt == nil)
            #expect(presence.endsAt == nil)
        }
        preferences.discordSharePaused = false
        preferences.discordTimerStyle = .hidden
        let reloaded = Preferences(defaults: defaults)
        #expect(!reloaded.discordSharePaused)
        #expect(reloaded.discordTimerStyle == .hidden)
    }

}

@Suite("Playback monitor reporting")
struct PlaybackMonitorReportingTests {
    @Test func updateIncludesPerProviderHealthAndTiming() async throws {
        let now = Date()
        let track = TrackMetadata(
            identity: .init(persistentID: "health"), title: "Track", artist: "Artist",
            album: nil, duration: 180, source: .appleMusicCatalog,
            appleMusicURL: nil, artworkReference: nil
        )
        let playback = PlaybackSnapshot(track: track, state: .playing, position: 1, observedAt: now, confidence: .high)
        let provider = StubPlaybackProvider(
            id: .appleMusic,
            value: ProviderSnapshot(provider: .appleMusic, playback: playback, health: .available, observedAt: now)
        )
        let monitor = PlaybackMonitor(credentials: CredentialStore(), providers: [.appleMusic: provider])
        await monitor.setEnabledProviders([.appleMusic])
        let stream = await monitor.snapshots()
        var iterator = stream.makeAsyncIterator()
        let update = try #require(await iterator.next())
        await monitor.stop()

        #expect(update.playback.track?.identity == track.identity)
        #expect(update.providerHealth[.appleMusic] == .available)
        #expect(update.providerHealth[.spotify] == .disabled)
        #expect(update.providerHealth[.youtubeMusic] == .disabled)
        #expect(update.providerHealth[.tidal] == .disabled)
        #expect(update.metrics.providerDurations[.appleMusic] != nil)
    }
}

@Suite("Observable status updates")
struct ObservableStatusUpdateTests {
    @Test @MainActor func repeatedStatusDoesNotWriteDuplicateHealth() throws {
        let store = try PersistenceStore(inMemory: true)
        let preferences = try #require(UserDefaults(suiteName: "AuraTests.status.\(UUID().uuidString)"))
        let model = AppModel(
            store: store,
            preferences: Preferences(defaults: preferences),
            notifications: NotificationCoordinator(delivery: StatusTestNotificationDelivery())
        )

        model.discordStatus = .connected
        model.discordStatus = .connected

        #expect(try store.context.fetchCount(FetchDescriptor<IntegrationHealthEvent>()) == 1)
    }
}

@MainActor
private final class StatusTestNotificationDelivery: NotificationDelivering {
    func requestAuthorization() async -> Bool { true }
    func deliver(identifier: String, title: String, body: String, section: DashboardSection) async {}
}

private struct StubPlaybackProvider: PlaybackProvider {
    let id: PlaybackProviderID
    let value: ProviderSnapshot
    func snapshot() async -> ProviderSnapshot { value }
}
