import Foundation
import Security

/// Stores and retrieves Nextcloud credentials in the system Keychain.
///
/// Uses a single Keychain item so the user is not prompted multiple times at launch.
/// Accessibility is set so the item can be read after the user has unlocked their Mac (at login)
/// without requiring Keychain password re-entry each time the app opens.
final class KeychainStorage {
    private static let service = "com.nextcloud.deck.macos"
    /// Single account key for all credentials (avoids three separate Keychain accesses at launch).
    private static let credentialsAccount = "credentials"
    /// Legacy keys for migration from the previous three-item format.
    private static let serverKey = "serverURL"
    private static let userKey = "username"
    private static let appPasswordKey = "appPassword"

    /// Accessibility: allow reading after first unlock (e.g. after login) without user prompt.
    /// Data remains encrypted and device-only; not accessible when device is locked before first unlock.
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    static func save(serverURL: URL, username: String, appPassword: String) throws {
        let payload = CredentialsPayload(
            serverURL: serverURL.absoluteString,
            username: username,
            appPassword: appPassword
        )
        guard let data = try? JSONEncoder().encode(payload) else {
            throw KeychainError.saveFailed(errSecParam)
        }
        try delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialsAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }

    static func load() -> (serverURL: URL, username: String, appPassword: String)? {
        if let creds = loadFromSingleItem() {
            return creds
        }
        if let creds = loadFromLegacyItems() {
            try? save(serverURL: creds.serverURL, username: creds.username, appPassword: creds.appPassword)
            try? deleteLegacyItems()
            return creds
        }
        return nil
    }

    /// One Keychain read for all credentials — avoids multiple prompts at launch.
    private static func loadFromSingleItem() -> (serverURL: URL, username: String, appPassword: String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialsAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        guard let payload = try? JSONDecoder().decode(CredentialsPayload.self, from: data),
              let url = URL(string: payload.serverURL) else { return nil }
        return (url, payload.username, payload.appPassword)
    }

    /// Migration: read legacy three-item format (one Keychain read per item).
    private static func loadFromLegacyItems() -> (serverURL: URL, username: String, appPassword: String)? {
        guard let server = getLegacy(serverKey),
              let username = getLegacy(userKey),
              let appPassword = getLegacy(appPasswordKey),
              let url = URL(string: server) else { return nil }
        return (url, username, appPassword)
    }

    private static func getLegacy(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() throws {
        try deleteSingleItem()
        try? deleteLegacyItems()
    }

    private static func deleteSingleItem() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialsAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.deleteFailed(status)
        }
    }

    private static func deleteLegacyItems() throws {
        for account in [serverKey, userKey, appPasswordKey] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                throw KeychainError.deleteFailed(status)
            }
        }
    }

    static var isLoggedIn: Bool { load() != nil }
}

private struct CredentialsPayload: Codable {
    let serverURL: String
    let username: String
    let appPassword: String
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let s): return "Keychain save failed: \(s)"
        case .deleteFailed(let s): return "Keychain delete failed: \(s)"
        }
    }
}
