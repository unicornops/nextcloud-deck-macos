import Foundation
import Security

/// Stores and retrieves Nextcloud credentials in the system Keychain.
///
/// Uses a single generic-password item so the user is not prompted multiple times at launch.
///
/// The item lives in the login (file-based) keychain, which ignores `kSecAttrAccessible`; it is readable
/// while the login keychain is unlocked and only by this app unless the user allows otherwise. Moving to
/// the data protection keychain (`kSecUseDataProtectionKeychain`) would honour accessibility classes, but
/// on macOS outside the App Store that needs a `keychain-access-groups` entitlement backed by a
/// provisioning profile, which release builds don't embed yet.
enum KeychainStorage {
    /// Service for stored credentials, under the app's own bundle identifier namespace.
    private static let service = "ie.unicornops.nextclouddeck"
    /// Service used by earlier versions. It is Nextcloud's reverse-DNS namespace, not ours, so stored
    /// credentials are moved from it to `service` on first launch.
    private static let previousService = "com.nextcloud.deck.macos"
    /// Single account key for all credentials (avoids three separate Keychain accesses at launch).
    private static let credentialsAccount = "credentials"
    /// Legacy keys for migration from the previous three-item format.
    private static let serverKey = "serverURL"
    private static let userKey = "username"
    private static let appPasswordKey = "appPassword"

    /// Ensures the URL uses HTTPS (required for security and App Store).
    private static func httpsURL(from url: URL) -> URL {
        guard url.scheme == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = "https"
        return components.url ?? url
    }

    /// Saves credentials and returns the server URL used for storage (always HTTPS).
    static func save(serverURL: URL, username: String, appPassword: String) throws -> URL {
        let urlToStore = Self.httpsURL(from: serverURL)
        let payload = CredentialsPayload(
            serverURL: urlToStore.absoluteString,
            username: username,
            appPassword: appPassword
        )
        guard let data = try? JSONEncoder().encode(payload) else {
            throw KeychainError.saveFailed(errSecParam)
        }
        try deleteItem(service: service, account: credentialsAccount)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialsAccount,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
        // Only once the new item is stored, so a failed save never loses the credentials it replaces.
        deletePreviousItems()
        return urlToStore
    }

    static func load() -> (serverURL: URL, username: String, appPassword: String)? {
        if let creds = loadFromSingleItem(service: service) {
            return creds
        }
        guard let creds = loadFromSingleItem(service: previousService) ?? loadFromLegacyItems() else {
            return nil
        }
        // Move credentials stored by an earlier version. If saving fails, keep using the old item and try
        // again on the next launch; `save` removes the old items once the new one is stored.
        let storedURL = try? save(serverURL: creds.serverURL, username: creds.username, appPassword: creds.appPassword)
        return (storedURL ?? creds.serverURL, creds.username, creds.appPassword)
    }

    /// One Keychain read for all credentials — avoids multiple prompts at launch.
    private static func loadFromSingleItem(service: String)
        -> (serverURL: URL, username: String, appPassword: String)? {
        guard let data = readItem(service: service, account: credentialsAccount),
              let payload = try? JSONDecoder().decode(CredentialsPayload.self, from: data),
              let url = URL(string: payload.serverURL) else { return nil }
        return (url, payload.username, payload.appPassword)
    }

    /// Migration: read the oldest three-item format (one Keychain read per item).
    private static func loadFromLegacyItems() -> (serverURL: URL, username: String, appPassword: String)? {
        guard let server = readString(service: previousService, account: serverKey),
              let username = readString(service: previousService, account: userKey),
              let appPassword = readString(service: previousService, account: appPasswordKey),
              let url = URL(string: server) else { return nil }
        return (url, username, appPassword)
    }

    private static func readString(service: String, account: String) -> String? {
        readItem(service: service, account: account).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func readItem(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete() throws {
        try deleteItem(service: service, account: credentialsAccount)
        deletePreviousItems()
    }

    /// Removes credentials left under `previousService` by earlier versions, in either format.
    private static func deletePreviousItems() {
        for account in [credentialsAccount, serverKey, userKey, appPasswordKey] {
            try? deleteItem(service: previousService, account: account)
        }
    }

    private static func deleteItem(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.deleteFailed(status)
        }
    }

    static var isLoggedIn: Bool {
        load() != nil
    }
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
        case let .saveFailed(s): "Keychain save failed: \(s)"
        case let .deleteFailed(s): "Keychain delete failed: \(s)"
        }
    }
}
