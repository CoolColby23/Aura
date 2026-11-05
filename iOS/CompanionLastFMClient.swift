import AuraCore
import AuthenticationServices
import Foundation
import UIKit

enum CompanionLastFMError: LocalizedError {
    case configuration, unauthorized, invalidResponse, accountChanged, api(String)
    /// Last.fm refused this play for a reason that cannot change on a retry.
    case rejected(String)
    /// Last.fm refused this play for a reason that can clear. `after` is the minimum wait.
    case retryLater(String, after: TimeInterval)
    var errorDescription: String? {
        switch self {
        case .configuration: "Enter your Last.fm API credentials in Aura."
        case .unauthorized: "Connect Last.fm in Settings."
        case .accountChanged: "Last.fm account changed before submission. The listen remains queued."
        case .invalidResponse: "Last.fm returned an invalid response."
        case .api(let message), .rejected(let message), .retryLater(let message, _): message
        }
    }

    /// True when resubmitting the same play cannot succeed.
    var isTerminal: Bool { if case .rejected = self { true } else { false } }

    /// How long to wait before another attempt. Terminal refusals are not retried.
    var retryDelay: TimeInterval? {
        switch self {
        case .retryLater(_, let after): after
        case .rejected: nil
        default: 30
        }
    }
}

enum CompanionSubmissionRetryPolicy {
    static func isSafeToRetry(_ error: any Error) -> Bool {
        switch error {
        case is CancellationError: true  // Only rate-slot sleep; URLSession uses URLError.cancelled.
        case let failure as CompanionLastFMError:
            switch failure {
            case .retryLater, .accountChanged, .configuration: true
            default: false
            }
        case let failure as URLError:
            [.cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet].contains(failure.code)
        default: false
        }
    }
}

/// A failed connection to a redirected endpoint would not prove that the
/// original POST was unsent. The API endpoint is fixed; refuse redirects so
/// the narrow connection-failure retry policy applies to the original request.
final class CompanionLastFMTaskDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct CompanionLastFMTrack: Identifiable, Hashable, Sendable {
    let title: String
    let artist: String
    let album: String?
    let artworkURL: URL?
    let playedAt: Date?
    let isNowPlaying: Bool

    var id: String {
        "\(artist)|\(title)|\(playedAt?.timeIntervalSince1970 ?? 0)|\(isNowPlaying)"
    }
}

actor CompanionLastFMClient {
    static let callbackURL = "https://presence-fm.vercel.app/lastfm-callback.html"
    private var credentials: CompanionLastFMCredentials
    private let keychain: CompanionKeychain
    private let session: URLSession
    private var earliestRequest = Date.distantPast

    init(credentials: CompanionLastFMCredentials, keychain: CompanionKeychain, session: URLSession = .shared) {
        self.credentials = credentials; self.keychain = keychain; self.session = session
    }

    func updateCredentials(_ credentials: CompanionLastFMCredentials) { self.credentials = credentials }

    func authorizationURL() async throws -> URL {
        let response = try await call(method: "auth.getToken", parameters: [:], sessionKey: nil)
        guard let token = response["token"] as? String,
            var components = URLComponents(string: "https://www.last.fm/api/auth/")
        else { throw CompanionLastFMError.invalidResponse }
        components.queryItems = [
            .init(name: "api_key", value: credentials.apiKey), .init(name: "token", value: token),
            .init(name: "cb", value: Self.callbackURL),
        ]
        guard let url = components.url else { throw CompanionLastFMError.invalidResponse }
        UserDefaults.standard.set(token, forKey: "AuraLastFMAuthToken")
        return url
    }

    func acceptCallback(_ url: URL) throws {
        guard url.scheme?.lowercased() == "aura",
            url.host?.lowercased() == "lastfm-auth"
        else { throw CompanionLastFMError.invalidResponse }
        if let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "token" })?.value
        {
            guard !token.isEmpty,
                token == UserDefaults.standard.string(forKey: "AuraLastFMAuthToken")
            else { throw CompanionLastFMError.invalidResponse }
        }
    }

    func hasPendingAuthorization() -> Bool {
        UserDefaults.standard.string(forKey: "AuraLastFMAuthToken")?.isEmpty == false
    }

    func completeAuthorization() async throws -> String {
        guard let token = UserDefaults.standard.string(forKey: "AuraLastFMAuthToken") else { throw CompanionLastFMError.unauthorized }
        let response = try await call(method: "auth.getSession", parameters: ["token": token], sessionKey: nil)
        guard let sessionObject = response["session"] as? [String: Any],
            let key = sessionObject["key"] as? String, let username = sessionObject["name"] as? String
        else {
            throw CompanionLastFMError.invalidResponse
        }
        try await keychain.setSession(key, username: username)
        UserDefaults.standard.removeObject(forKey: "AuraLastFMAuthToken")
        return username
    }

    func username() async -> String? { await keychain.value(for: .lastFMUsername) }

    func recentTracks(username: String, limit: Int = 200, maxPages: Int = 10) async throws -> [CompanionLastFMTrack] {
        let limit = min(max(limit, 1), 200)
        let maxPages = max(maxPages, 1)
        var result: [CompanionLastFMTrack] = []
        for page in 1...maxPages {
            let response = try await call(
                method: "user.getRecentTracks",
                parameters: ["user": username, "limit": String(limit), "page": String(page), "extended": "0"],
                sessionKey: nil)
            guard let recent = response["recenttracks"] as? [String: Any] else {
                throw CompanionLastFMError.invalidResponse
            }
            let rawTracks: [[String: Any]]
            if let tracks = recent["track"] as? [[String: Any]] {
                rawTracks = tracks
            } else if let track = recent["track"] as? [String: Any] {
                rawTracks = [track]
            } else {
                rawTracks = []
            }
            result.append(contentsOf: rawTracks.compactMap(Self.parseRecentTrack))
            let attributes = recent["@attr"] as? [String: Any]
            let totalPages =
                (attributes?["totalPages"] as? String).flatMap(Int.init)
                ?? (attributes?["totalPages"] as? NSNumber)?.intValue
            if rawTracks.count < limit || page >= (totalPages ?? page + 1) { break }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.id).inserted }
    }

    private static func parseRecentTrack(_ track: [String: Any]) -> CompanionLastFMTrack? {
        guard let title = track["name"] as? String,
            let artistObject = track["artist"] as? [String: Any],
            let artist = artistObject["#text"] as? String
        else { return nil }
        let attributes = track["@attr"] as? [String: Any]
        let dateObject = track["date"] as? [String: Any]
        let timestamp = (dateObject?["uts"] as? String).flatMap(TimeInterval.init)
        let images = track["image"] as? [[String: Any]]
        let artwork = images?.reversed().compactMap { image -> URL? in
            guard let raw = image["#text"] as? String, !raw.isEmpty else { return nil }
            return URL(string: raw)
        }.first
        let album = (track["album"] as? [String: Any])?["#text"] as? String
        return CompanionLastFMTrack(
            title: title, artist: artist, album: album?.isEmpty == false ? album : nil,
            artworkURL: artwork, playedAt: timestamp.map(Date.init(timeIntervalSince1970:)),
            isNowPlaying: attributes?["nowplaying"] as? String == "true")
    }

    func disconnect() async throws {
        try await keychain.setSession(nil, username: nil)
        UserDefaults.standard.removeObject(forKey: "AuraLastFMAuthToken")
    }

    func updateNowPlaying(_ metadata: ScrobbleMetadata) async throws {
        let sessionKey = try await requiredSession()
        var parameters = ["track": metadata.title, "artist": metadata.artist]
        if let album = metadata.album { parameters["album"] = album }
        if let duration = metadata.duration { parameters["duration"] = String(Int(duration)) }
        _ = try await call(method: "track.updateNowPlaying", parameters: parameters, sessionKey: sessionKey)
    }

    func scrobble(_ metadata: ScrobbleMetadata, expectedUsername: String) async throws {
        guard let startedAt = metadata.startedAt else { throw CompanionLastFMError.invalidResponse }
        // Bind the network request to the account that owns the CloudKit lease.
        // The captured session remains that account's even across rate-limit waits.
        guard let sessionKey = await keychain.session(for: expectedUsername), !sessionKey.isEmpty else {
            throw CompanionLastFMError.accountChanged
        }
        var parameters = [
            "track": metadata.title, "artist": metadata.artist,
            "timestamp": String(Int(startedAt.timeIntervalSince1970)),
        ]
        if let album = metadata.album { parameters["album"] = album }
        if let duration = metadata.duration { parameters["duration"] = String(Int(duration)) }
        let response = try await call(method: "track.scrobble", parameters: parameters, sessionKey: sessionKey)
        switch LastFMScrobbleResponse.interpret(response) {
        case .accepted:
            return
        case .rejected(let message):
            throw CompanionLastFMError.rejected(message)
        case .retryLater(let message, let minimumDelay):
            throw CompanionLastFMError.retryLater(message, after: minimumDelay)
        case nil:
            throw CompanionLastFMError.invalidResponse
        }
    }

    private func requiredSession() async throws -> String {
        guard let value = await keychain.value(for: .lastFMSession), !value.isEmpty else { throw CompanionLastFMError.unauthorized }
        return value
    }

    private func call(method: String, parameters: [String: String], sessionKey: String?) async throws -> [String: Any] {
        guard credentials.isConfigured else { throw CompanionLastFMError.configuration }
        // Reserve this request's slot before suspending. Actor methods are
        // reentrant across `await`, so updating the deadline after sleeping can
        // let several callers wake and hit Last.fm at the same time.
        let now = Date()
        let requestAt = max(now, earliestRequest)
        earliestRequest = requestAt.addingTimeInterval(0.35)
        let delay = requestAt.timeIntervalSince(now)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        let values = LastFMRequestBuilder.values(
            method: method, parameters: parameters, apiKey: credentials.apiKey, secret: credentials.sharedSecret, sessionKey: sessionKey)
        var request = URLRequest(url: URL(string: "https://ws.audioscrobbler.com/2.0/")!)
        request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = LastFMRequestBuilder.body(values)
        let (data, response) = try await session.data(for: request, delegate: CompanionLastFMTaskDelegate())
        guard let http = response as? HTTPURLResponse else { throw CompanionLastFMError.invalidResponse }
        if http.statusCode == 429 {
            let rawDelay = TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 30
            let retryAfter = rawDelay.isFinite ? min(300, max(5, rawDelay)) : 30
            earliestRequest = max(earliestRequest, Date().addingTimeInterval(retryAfter))
            throw CompanionLastFMError.retryLater("Last.fm is busy. Aura will retry automatically.", after: retryAfter)
        }
        guard (200...299).contains(http.statusCode),
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw CompanionLastFMError.invalidResponse }
        if let message = object["message"] as? String {
            let code = (object["error"] as? Int) ?? (object["error"] as? String).flatMap(Int.init)
            if code == 29 || code == 11 || code == 16 {
                earliestRequest = max(earliestRequest, Date().addingTimeInterval(30))
                throw CompanionLastFMError.retryLater(message, after: 30)
            }
            throw CompanionLastFMError.api(message)
        }
        return object
    }
}
