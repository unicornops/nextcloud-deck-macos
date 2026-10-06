import Foundation
import Security

/// Where `AppState` keeps the credentials of every signed-in account.
protocol CredentialStore {
    /// The saved accounts; empty if there are none or they can't be read.
    func load() -> SavedAccounts
    /// Replaces the saved accounts; saving none removes them.
    func save(_ accounts: SavedAccounts) throws
}

/// The app's credential store: the system Keychain, via `KeychainStorage`.
struct KeychainCredentialStore: CredentialStore {
    func load() -> SavedAccounts {
        KeychainStorage.load()
    }

    func save(_ accounts: SavedAccounts) throws {
        try KeychainStorage.save(accounts)
    }
}

/// Stores and retrieves Nextcloud credentials in the system Keychain.
///
/// Uses a single generic-password item holding every account (`SavedAccounts`), so the user is not prompted
/// multiple times at launch. Each account in it is keyed by user and server (`Account.id`).
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

    /// Saves every account, replacing what was stored; with no accounts left, removes the item.
    /// Updates the item in place, so a failed write never loses the accounts already saved.
    static func save(_ accounts: SavedAccounts) throws {
        guard !accounts.all.isEmpty else {
            try deleteItem(service: service, account: credentialsAccount)
            return
        }
        guard let data = try? JSONEncoder().encode(accounts) else {
            throw KeychainError.saveFailed(errSecParam)
        }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialsAccount,
        ]
        var status = SecItemUpdate(item as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(item.merging([kSecValueData as String: data]) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }

    static func load() -> SavedAccounts {
        guard let data = readItem(service: service, account: credentialsAccount),
              let accounts = try? JSONDecoder().decode(SavedAccounts.self, from: data) else { return SavedAccounts() }
        return accounts
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
