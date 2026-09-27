import Foundation

/// How Last.fm answered a single `track.scrobble` call.
///
/// Ignored codes 1–3 describe the play itself and will fail again on retry.
/// Code 4 is a timestamp still in the future, and code 5 is the daily limit;
/// both clear with time. Anything else unrecognized stays retryable so a play
/// is not dropped because the response shape drifted.
public enum LastFMScrobbleOutcome: Equatable, Sendable {
    case accepted
    case rejected(String)
    case retryLater(message: String, minimumDelay: TimeInterval)
}

public enum LastFMScrobbleResponse {
    /// Long enough for a few minutes of clock skew to fall behind the timestamp.
    public static let futureTimestampDelay: TimeInterval = 15 * 60
    /// Last.fm resets the daily limit on a day boundary Aura cannot see.
    public static let dailyLimitDelay: TimeInterval = 6 * 60 * 60
    /// Used when Last.fm refuses a play without a known ignored code.
    public static let unspecifiedRetryDelay: TimeInterval = 5 * 60

    /// `nil` when the payload is not a scrobble response.
    public static func interpret(_ response: [String: Any]) -> LastFMScrobbleOutcome? {
        guard let scrobbles = response["scrobbles"] as? [String: Any],
            let attributes = scrobbles["@attr"] as? [String: Any],
            let accepted = integer(attributes["accepted"])
        else { return nil }
        guard accepted == 1 else { return refusal(from: scrobbles) }
        return .accepted
    }

    private static func refusal(from scrobbles: [String: Any]) -> LastFMScrobbleOutcome {
        let entry =
            (scrobbles["scrobble"] as? [String: Any])
            ?? (scrobbles["scrobble"] as? [[String: Any]])?.first
        let ignored =
            (entry?["ignoredMessage"] as? [String: Any])
            ?? (entry?["ignoredmessage"] as? [String: Any])
        let text = (ignored?["#text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = codeString(ignored?["code"])
        let message = message(text: text, code: code)
        switch code {
        case "1", "2", "3":
            return .rejected(message)
        case "4":
            return .retryLater(message: message, minimumDelay: futureTimestampDelay)
        case "5":
            return .retryLater(message: message, minimumDelay: dailyLimitDelay)
        default:
            return .retryLater(message: message, minimumDelay: unspecifiedRetryDelay)
        }
    }

    private static func message(text: String?, code: String?) -> String {
        if let text, !text.isEmpty { return text }
        switch code {
        case "1": return "Last.fm filtered the artist."
        case "2": return "Last.fm filtered the track."
        case "3": return "This play is too old for Last.fm to accept."
        case "4": return "This play time is too far in the future."
        case "5": return "The Last.fm daily scrobble limit was reached."
        default: return "Last.fm did not accept the scrobble."
        }
    }

    private static func codeString(_ value: Any?) -> String? {
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = integer(value) { return String(value) }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? String { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}
