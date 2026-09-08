import AuraCore
import Foundation
import XCTest

@testable import AuraiOS

final class CompanionReliabilityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        CompanionURLProtocol.reset()
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

    func testHistoryExpansionHonorsIncrementalScanCursor() {
        let newest = Date(timeIntervalSince1970: 10_000)
        let dates = AppleMusicEvidenceSource.inferredPlayDates(
            lastPlayedAt: newest, playCount: 10, duration: 180,
            since: newest.addingTimeInterval(-400))

        XCTAssertEqual(dates, [newest, newest.addingTimeInterval(-180), newest.addingTimeInterval(-360)])
    }

    private func makeClient() -> CompanionLastFMClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CompanionURLProtocol.self]
        return CompanionLastFMClient(
            credentials: .init(apiKey: "api-key", sharedSecret: "secret"),
            keychain: CompanionKeychain(),
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
