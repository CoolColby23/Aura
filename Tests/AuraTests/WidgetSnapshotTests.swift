import Foundation
import Testing

@testable import Aura

@MainActor
struct WidgetSnapshotTests {
    @Test func privateSnapshotRedactsPersistedMetadataAndProgress() throws {
        let track = TrackMetadata(
            identity: .init(persistentID: "secret"), title: "Secret track", artist: "Secret artist", album: "Secret album", duration: 180,
            source: .appleMusicCatalog, appleMusicURL: nil, artworkReference: nil, platform: .spotify)
        let playback = PlaybackSnapshot(track: track, state: .playing, position: 42, observedAt: .now, confidence: .high)
        let publicSnapshot = WidgetSnapshotService.snapshot(playback, isPrivate: false)
        #expect(publicSnapshot.title == "Secret track")
        #expect(publicSnapshot.position == 42)
        let privateSnapshot = WidgetSnapshotService.snapshot(playback, isPrivate: true)
        let encoded = String(decoding: try JSONEncoder().encode(privateSnapshot), as: UTF8.self)
        #expect(!encoded.contains("Secret"))
        #expect(privateSnapshot.platform == "Aura")
        #expect(privateSnapshot.position == 0)
        #expect(privateSnapshot.duration == 0)
        #expect(privateSnapshot.isPrivate)
    }
}
