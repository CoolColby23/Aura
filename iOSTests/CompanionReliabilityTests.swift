import AuraCore
import Foundation
import XCTest

@testable import AuraiOS

final class CompanionReliabilityTests: XCTestCase {
    func testRepeatedPlaysPersistWithDistinctIDsAndRetainLegacyID() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ledger.json")
        let store = CompanionStore(fileURL: url)
        let start = Date(timeIntervalSince1970: 2041)
        try await store.establishBaselineIfNeeded(.init(establishedAt: start.addingTimeInterval(-1)))
        func evidence(_ offset: TimeInterval) -> PlaybackEvidence {
            PlaybackEvidence(
                deviceID: UUID(), sourceTrackID: "repeat",
                metadata: .init(title: "Track", artist: "Artist", duration: 180, startedAt: start.addingTimeInterval(offset)), observedPlayTime: 120,
                origin: .observed, confidence: .strong, capturedAt: start.addingTimeInterval(offset + 120))
        }
        let first = try await store.ingest(evidence(0))
        try await store.setState(.submitted, for: first.id, submittedAt: start)
        let second = try await store.ingest(evidence(99))
        XCTAssertNotEqual(first.id, second.id)
        let reloaded = CompanionStore(fileURL: url)
        let state = await reloaded.current()
        XCTAssertEqual(state.listens.count, 2)
        XCTAssertEqual(state.listens.first?.state, .submitted)
        XCTAssertEqual(state.listens.last?.state, .queued)
        let again = try await reloaded.ingest(evidence(99))
        XCTAssertEqual(again.id, second.id)
        let final = await reloaded.current()
        XCTAssertEqual(final.listens.count, 2)
    }

    func testLegacyDuplicateIDsCannotMarkTheWrongPlaySubmitted() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("ledger.json")
        let start = Date(timeIntervalSince1970: 2041)
        func legacy(_ offset: TimeInterval) -> CanonicalListen {
            let item = PlaybackEvidence(
                deviceID: UUID(), sourceTrackID: "repeat", metadata: .init(title: "Track", artist: "Artist", startedAt: start.addingTimeInterval(offset)),
                observedPlayTime: 120, origin: .observed, confidence: .strong)
            return CanonicalListen(id: CanonicalListenIdentity.legacy(for: item), evidence: [item], metadata: item.originalMetadata, state: .queued)
        }
        let one = legacy(0), two = legacy(99)
        XCTAssertEqual(one.id, two.id)
        var fixture = CompanionSnapshot.empty
        fixture.listens = [one, two]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(fixture).write(to: url)
        let original = try Data(contentsOf: url)
        let store = CompanionStore(fileURL: url)
        do { try await store.setState(.submitted, for: one.id); XCTFail("Ambiguous legacy key accepted") } catch CompanionStoreError.ambiguousListenID {}
        XCTAssertEqual(try Data(contentsOf: url), original)
        let evidence = two.evidence[0]
        do { _ = try await store.ingest(evidence); XCTFail("Passive capture merged a duplicate key") } catch CompanionStoreError.ambiguousListenID {}
        do { try await store.ingest([evidence]); XCTFail("Batch capture merged a duplicate key") } catch CompanionStoreError.ambiguousListenID {}
        XCTAssertEqual(try Data(contentsOf: url), original)
        let preserved = await store.current()
        XCTAssertEqual(preserved.listens, fixture.listens)
    }

    override func setUp() {
        super.setUp()
        CompanionURLProtocol.reset()
    }

    func testRateLimitIsDefiniteRetryWithFiniteDelay() async throws {
        for header in ["45", "nan", "inf", "-10"] {
            CompanionURLProtocol.handler = { request in
                (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": header])!, Data())
            }
            do { _ = try await makeClient().recentTracks(username: "listener"); XCTFail("Rate limit ignored") } catch CompanionLastFMError.retryLater(
                _, let delay)
            {
                XCTAssertTrue(delay.isFinite)
                XCTAssertGreaterThanOrEqual(delay, 5)
                XCTAssertLessThanOrEqual(delay, 300)
                if header == "45" { XCTAssertEqual(delay, 45) }
            }
        }
    }

    func testAccountSwitchCannotUseNewSessionForOldLease() async throws {
        let keychain = CompanionKeychain(inMemoryValues: [:])
        do {
            try await keychain.setSession("session-a", username: "ListenerA")
            let client = makeClient(keychain: keychain)
            try await keychain.setSession("session-b", username: "ListenerB")
            do {
                try await client.scrobble(.init(title: "Track", artist: "Artist", startedAt: .now), expectedUsername: "listenera")
                XCTFail("Old lease used the new account")
            } catch CompanionLastFMError.accountChanged {}
            XCTAssertEqual(CompanionURLProtocol.requestCount, 0)
            let session = await keychain.session(for: " LISTENERB ")
            XCTAssertEqual(session, "session-b")
            try await keychain.setSession(nil, username: nil)
            let cleared = await keychain.session(for: "listenerb")
            XCTAssertNil(cleared)
        } catch {
            try? await keychain.setSession(nil, username: nil)
            throw error
        }
    }

    func testLeaseAccountMismatchDoesNotSendRequest() async throws {
        // Empty expected identity cannot match an authorized account. This test
        // never writes credentials or touches a real Last.fm account.
        do {
            try await makeClient().scrobble(.init(title: "Track", artist: "Artist", startedAt: .now), expectedUsername: "")
            XCTFail("Unbound account submitted")
        } catch CompanionLastFMError.accountChanged {}
        XCTAssertEqual(CompanionURLProtocol.requestCount, 0)
    }

    func testRecentTracksBoundsPaginationAndDeduplicatesResults() async throws {
        CompanionURLProtocol.handler = { request in
            let values = Self.formValues(request)
            XCTAssertEqual(values["limit"], "200")
            let page = Int(values["page"] ?? "0") ?? 0
            let track = Self.trackJSON(title: page == 1 ? "First" : "Second", timestamp: "100")
            let data = try JSONSerialization.data(withJSONObject: [
                "recenttracks": [
                    "track": page == 1 ? Array(repeating: track, count: 200) : [track],
                    "@attr": ["totalPages": "2"],
                ]
            ])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let client = makeClient()
        let tracks = try await client.recentTracks(username: "listener", limit: 500, maxPages: 2)

        XCTAssertEqual(tracks.map(\.title), ["First", "Second"])
        XCTAssertEqual(CompanionURLProtocol.requestCount, 2)
    }

    func testRecentTracksTreatsNonpositivePageCountAsOnePage() async throws {
        CompanionURLProtocol.handler = { request in
            let data = try JSONSerialization.data(withJSONObject: [
                "recenttracks": ["track": [], "@attr": ["totalPages": "5"]]
            ])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        _ = try await makeClient().recentTracks(username: "listener", maxPages: 0)

        XCTAssertEqual(CompanionURLProtocol.requestCount, 1)
    }

    func testConcurrentRequestsReserveSeparateRateLimitSlots() async throws {
        CompanionURLProtocol.handler = { request in
            let data = try JSONSerialization.data(withJSONObject: ["recenttracks": ["track": []]])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let client = makeClient()

        async let first = client.recentTracks(username: "one", maxPages: 1)
        async let second = client.recentTracks(username: "two", maxPages: 1)
        _ = try await (first, second)

        let dates = CompanionURLProtocol.requestDates.sorted()
        XCTAssertEqual(dates.count, 2)
        XCTAssertGreaterThanOrEqual(dates[1].timeIntervalSince(dates[0]), 0.25)
    }

    func testCorrectionRejectsBlankRequiredMetadataAndNormalizesAlbum() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Aura-iOSTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CompanionStore(fileURL: directory.appendingPathComponent("ledger.json"))
        let evidence = PlaybackEvidence(
            deviceID: UUID(),
            sourceTrackID: "track",
            metadata: .init(title: "Original", artist: "Artist", duration: 180, startedAt: .now),
            observedPlayTime: 100,
            origin: .observed,
            confidence: .strong
        )
        let listen = try await store.ingest(evidence)

        do {
            try await store.correct(id: listen.id, title: "   ", artist: "Artist", album: nil)
            XCTFail("Blank corrected metadata should be rejected")
        } catch is CompanionStoreError {
            // Expected.
        }

        try await store.correct(id: listen.id, title: " Corrected ", artist: " Artist ", album: "   ")
        let snapshot = await store.current()
        let corrected = try XCTUnwrap(snapshot.listens.first)
        XCTAssertEqual(corrected.canonicalMetadata.title, "Corrected")
        XCTAssertEqual(corrected.canonicalMetadata.artist, "Artist")
        XCTAssertNil(corrected.canonicalMetadata.album)
    }

    func testHistoryExpansionMatchesMediaPlayCountAndKeepsDistinctTimestamps() {
        let newest = Date(timeIntervalSince1970: 100_000)
        let dates = AppleMusicEvidenceSource.inferredPlayDates(
            lastPlayedAt: newest, playCount: 97, duration: 180,
            since: .distantPast)

        XCTAssertEqual(dates.count, 97)
        XCTAssertEqual(dates.first, newest)
        XCTAssertEqual(dates[0].timeIntervalSince(dates[1]), 180)
        XCTAssertEqual(Set(dates).count, 97)
    }

    func testRetryDelayFollowsTheSharedLastFMDecision() {
        let dailyLimit = CompanionLastFMError.retryLater(
            "The Last.fm daily scrobble limit was reached.",
            after: LastFMScrobbleResponse.dailyLimitDelay
        )
        XCTAssertEqual(dailyLimit.retryDelay, LastFMScrobbleResponse.dailyLimitDelay)
        XCTAssertFalse(dailyLimit.isTerminal)
        XCTAssertNil(CompanionLastFMError.rejected("Last.fm filtered the artist.").retryDelay)
        XCTAssertTrue(CompanionLastFMError.rejected("Last.fm filtered the artist.").isTerminal)
        XCTAssertEqual(CompanionLastFMError.api("Last.fm is busy. Aura will retry automatically.").retryDelay, 30)
    }

    func testHistoryExpansionHonorsIncrementalScanCursor() {
        let newest = Date(timeIntervalSince1970: 10_000)
        let dates = AppleMusicEvidenceSource.inferredPlayDates(
            lastPlayedAt: newest, playCount: 10, duration: 180,
            since: newest.addingTimeInterval(-400))

        XCTAssertEqual(dates, [newest, newest.addingTimeInterval(-180), newest.addingTimeInterval(-360)])
    }

    private func makeClient(keychain: CompanionKeychain = CompanionKeychain(inMemoryValues: [:])) -> CompanionLastFMClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CompanionURLProtocol.self]
        return CompanionLastFMClient(
            credentials: .init(apiKey: "api-key", sharedSecret: "secret"),
            keychain: keychain,
            session: URLSession(configuration: configuration)
        )
    }

    private static func formValues(_ request: URLRequest) -> [String: String] {
        let data: Data?
        if let body = request.httpBody {
            data = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var result = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: 4_096)
                guard count > 0 else { break }
                result.append(buffer, count: count)
            }
            data = result
        } else {
            data = nil
        }
        guard let data, let body = String(data: data, encoding: .utf8) else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: body.split(separator: "&").compactMap { pair in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return (
                    parts[0].removingPercentEncoding ?? parts[0],
                    parts[1].removingPercentEncoding ?? parts[1]
                )
            })
    }

    private static func trackJSON(title: String, timestamp: String) -> [String: Any] {
        [
            "name": title,
            "artist": ["#text": "Artist"],
            "album": ["#text": "Album"],
            "date": ["uts": timestamp],
            "image": [],
        ]
    }
}

private final class CompanionURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private static let lock = NSLock()
    nonisolated(unsafe) private static var dates: [Date] = []

    static var requestDates: [Date] { lock.withLock { dates } }
    static var requestCount: Int { requestDates.count }

    static func reset() {
        lock.withLock { dates = [] }
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.dates.append(.now) }
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
