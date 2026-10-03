import Foundation
import Security

/// Where `AppState` keeps the signed-in user's credentials.
protocol CredentialStore {
    func load() -> (serverURL: URL, username: String, appPassword: String)?
    /// Saves credentials and returns the server URL as stored.
    func save(serverURL: URL, username: String, appPassword: String) throws -> URL
    func delete() throws
}

/// The app's credential store: the system Keychain, via `KeychainStorage`.
struct KeychainCredentialStore: CredentialStore {
    func load() -> (serverURL: URL, username: String, appPassword: String)? {
        KeychainStorage.load()
    }

    func save(serverURL: URL, username: String, appPassword: String) throws -> URL {
        try KeychainStorage.save(serverURL: serverURL, username: username, appPassword: appPassword)
    }

    func delete() throws {
        try KeychainStorage.delete()
    }
}

/// Stores and retrieves Nextcloud credentials in the system Keychain.
///
/// Uses a single generic-password item so the user is not prompted multiple times at launch.
///
/// The item lives in the login (file-based) keychain, which ignores `kSecAttrAccessible`; it is readable
/// while the login keychain is unlocked and only by this app unless the user allows otherwise. Moving to
/// the data protection keychain (`kSecUseDataProtectionKeychain`) would honour accessibility classes, but
/// on macOS outside the App Store that needs a `keychain-access-groups` entitlement backed by a
/// provisioning profile, which release builds don't embed yet.
///
/// Versions released as "Nextcloud Deck" (bundle ID `ie.unicornops.nextclouddeck`) stored credentials under
/// other services. Shuffleboard is a different app identity, so it can't read those items without macOS
/// asking the user for permission; rather than prompt at launch, it leaves them alone and the user signs in
/// once (see "Upgrading" in the README).
enum KeychainStorage {
    /// Service for stored credentials: the app's bundle identifier.
    private static let service = "ie.unicornops.shuffleboard"
    /// Single account key for all credentials (avoids several Keychain accesses at launch).
    private static let credentialsAccount = "credentials"

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
        return urlToStore
    }

    static func load() -> (serverURL: URL, username: String, appPassword: String)? {
        guard let data = readItem(service: service, account: credentialsAccount),
              let payload = try? JSONDecoder().decode(CredentialsPayload.self, from: data),
              let url = URL(string: payload.serverURL) else { return nil }
        return (url, payload.username, payload.appPassword)
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
