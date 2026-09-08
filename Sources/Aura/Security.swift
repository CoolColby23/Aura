import Foundation

enum Credential: String, CaseIterable, Sendable {
    case discordApplicationID, lastFMAPIKey, lastFMSecret, lastFMAuthToken, lastFMSessionKey, lastFMUsername, ytmDesktopToken
}

/// Stores credentials without invoking macOS Keychain. Ad-hoc signed builds change
/// identity between releases, which makes Keychain repeatedly request the user's
/// password. This owner-only file works consistently for free, unsigned distribution.
actor CredentialStore {
    private let fileURL: URL
    private var values: [String: String]

    init(baseDirectory: URL? = nil) {
        let directory =
            baseDirectory
            ?? FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!.appendingPathComponent("Aura", isDirectory: true)
        fileURL = directory.appendingPathComponent("credentials.json")
        if let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        {
            values = decoded
        } else if let adopted = Self.legacyValues(newDirectory: directory) {
            // The app shipped as PresenceFM through v1.3. Adopt that credential
            // file once so a rebranded build keeps the user signed in to Last.fm
            // and Discord instead of silently starting disconnected.
            values = adopted
            try? Self.write(adopted, to: fileURL)
        } else {
            values = [:]
        }
    }

    /// Credentials written by PresenceFM builds, read only when this build has
    /// none of its own. Returns `nil` when the legacy file is absent or unreadable.
    private static func legacyValues(newDirectory: URL) -> [String: String]? {
        let legacyURL =
            newDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("PresenceFM", isDirectory: true)
            .appendingPathComponent("credentials.json")
        guard let data = try? Data(contentsOf: legacyURL),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return nil }
        return decoded
    }

    func set(_ value: String, for credential: Credential) throws {
        if value.isEmpty { values.removeValue(forKey: credential.rawValue) } else { values[credential.rawValue] = value }
        try persist()
    }

    func value(for credential: Credential) -> String? {
        values[credential.rawValue]
    }

    func remove(_ credential: Credential) throws {
        values.removeValue(forKey: credential.rawValue)
        try persist()
    }

    private func persist() throws {
        try Self.write(values, to: fileURL)
    }

    private static func write(_ values: [String: String], to fileURL: URL) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(values)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
