import Foundation
import Security

actor CompanionKeychain {
    enum Key: String { case lastFMAPIKey, lastFMSharedSecret, lastFMSession, lastFMUsername, deviceID }
    private let service: String
    /// The service the companion used while the app shipped as PresenceFM.
    private let legacyService: String

    init(service: String = "fm.aura.companion", legacyService: String = "fm.presence.companion") {
        self.service = service; self.legacyService = legacyService
    }

    func value(for key: Key) -> String? {
        if let value = read(key, service: service) { return value }
        // Adopt the PresenceFM-era item once so upgrading users keep their Last.fm
        // session and device identity instead of being asked to authorize again.
        guard let legacy = read(key, service: legacyService) else { return nil }
        if (try? set(legacy, for: key)) != nil { delete(key, service: legacyService) }
        return legacy
    }

    // Read both items in one actor turn so an authorization change cannot pair
    // one account's username with another account's session key.
    func session(for expectedUsername: String) -> String? {
        guard
            value(for: .lastFMUsername)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == expectedUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        else { return nil }
        return value(for: .lastFMSession)
    }

    func setSession(_ session: String?, username: String?) throws {
        // Remove the identity first: a partial Keychain write must fail closed.
        try set(nil, for: .lastFMUsername)
        try set(session, for: .lastFMSession)
        try set(username, for: .lastFMUsername)
    }

    private func read(_ key: Key, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(_ key: Key, service: String) {
        _ = SecItemDelete(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key.rawValue,
            ] as CFDictionary)
    }

    func set(_ value: String?, for key: Key) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        guard let value else {
            let status = SecItemDelete(base as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.status(status)
            }
            delete(key, service: legacyService)
            return
        }
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            base as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError.status(updateStatus) }
        var insert = base
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func stableDeviceID() throws -> UUID {
        if let raw = value(for: .deviceID), let id = UUID(uuidString: raw) { return id }
        let id = UUID(); try set(id.uuidString, for: .deviceID); return id
    }
}

enum KeychainError: LocalizedError { case status(OSStatus); var errorDescription: String? { "Keychain operation failed." } }
