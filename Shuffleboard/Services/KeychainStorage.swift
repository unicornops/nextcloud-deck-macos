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
    var storage = KeychainStorage()

    func load() -> SavedAccounts {
        storage.load()
    }

    func save(_ accounts: SavedAccounts) throws {
        try storage.save(accounts)
    }
}

// MARK: - KeychainStorage

/// Stores and retrieves Nextcloud credentials in the system Keychain.
///
/// Uses a single generic-password item holding every account (`SavedAccounts`), so the user is not prompted
/// multiple times at launch. Each account in it is keyed by user and server (`Account.id`).
///
/// The item lives in the data protection keychain, readable only by this app, only on this Mac and only once
/// the Mac has been unlocked since it started (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) (#92). On
/// macOS outside the App Store that keychain needs the `keychain-access-groups` entitlement backed by a
/// provisioning profile, which only release builds have; builds without it (Debug, CI, ad-hoc signed) get
/// `errSecMissingEntitlement` and keep using the login (file-based) keychain, as versions before 0.20 did.
/// The first time a release build finds an item there, it moves it to the data protection keychain.
///
/// Versions released as "Nextcloud Deck" (bundle ID `ie.unicornops.nextclouddeck`) stored credentials under
/// other services. Shuffleboard is a different app identity, so it can't read those items without macOS
/// asking the user for permission; rather than prompt at launch, it leaves them alone and the user signs in
/// once (see "Upgrading" in the README).
struct KeychainStorage {
    var items: KeychainItems = SystemKeychainItems()

    /// Saves every account, replacing what was stored; with no accounts left, removes the item.
    /// Updates the item in place, so a failed write never loses the accounts already saved.
    func save(_ accounts: SavedAccounts) throws {
        guard !accounts.all.isEmpty else {
            for keychain in Keychain.allCases {
                let status = items.delete(from: keychain)
                // Gone already, or a keychain this build can't use: nothing to remove.
                let removed: Set<OSStatus> = [errSecSuccess, errSecItemNotFound, errSecMissingEntitlement]
                guard removed.contains(status) else { throw KeychainError.deleteFailed(status) }
            }
            return
        }
        guard let data = try? JSONEncoder().encode(accounts) else {
            throw KeychainError.saveFailed(errSecParam)
        }
        var status = items.write(data, to: .dataProtection)
        if status == errSecMissingEntitlement {
            status = items.write(data, to: .file)
        } else if status == errSecSuccess {
            // An older copy left in the login keychain would come back if this one were lost.
            _ = items.delete(from: .file)
        }
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }

    /// The saved accounts, from the data protection keychain, or else the login keychain (moving them to the data
    /// protection keychain when this build can use it).
    func load() -> SavedAccounts {
        let (status, data) = items.read(from: .dataProtection)
        if status == errSecSuccess, let accounts = Self.decode(data) {
            return accounts
        }
        let (_, fileData) = items.read(from: .file)
        guard let accounts = Self.decode(fileData), let fileData else { return SavedAccounts() }
        // Only delete the old item once the new one is written; if the move fails, try again next launch.
        if status != errSecMissingEntitlement, items.write(fileData, to: .dataProtection) == errSecSuccess {
            _ = items.delete(from: .file)
        }
        return accounts
    }

    private static func decode(_ data: Data?) -> SavedAccounts? {
        data.flatMap { try? JSONDecoder().decode(SavedAccounts.self, from: $0) }
    }
}

/// The two macOS keychains an item can be in.
enum Keychain: CaseIterable, Sendable {
    /// The modern, iOS-style keychain (`kSecUseDataProtectionKeychain`); needs a provisioning profile.
    case dataProtection
    /// The login keychain, a file in `~/Library/Keychains`.
    case file
}

/// The credentials item in each keychain, so `KeychainStorage`'s choice between them can be tested without the
/// real Keychain. Each call returns the `SecItem` status.
protocol KeychainItems {
    func read(from keychain: Keychain) -> (OSStatus, Data?)
    /// Creates the item or replaces its data.
    func write(_ data: Data, to keychain: Keychain) -> OSStatus
    func delete(from keychain: Keychain) -> OSStatus
}

/// The credentials item in the system Keychain.
struct SystemKeychainItems: KeychainItems {
    /// Service for stored credentials: the app's bundle identifier.
    private static let service = "ie.unicornops.shuffleboard"
    /// Single account key for all credentials (avoids several Keychain accesses at launch).
    private static let account = "credentials"

    private func query(_ keychain: Keychain) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        if keychain == .dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    func read(from keychain: Keychain) -> (OSStatus, Data?) {
        var query = query(keychain)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, status == errSecSuccess ? result as? Data : nil)
    }

    func write(_ data: Data, to keychain: Keychain) -> OSStatus {
        let item = query(keychain)
        var attributes: [String: Any] = [kSecValueData as String: data]
        if keychain == .dataProtection {
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        let status = SecItemUpdate(item as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else { return status }
        return SecItemAdd(item.merging(attributes) { $1 } as CFDictionary, nil)
    }

    func delete(from keychain: Keychain) -> OSStatus {
        SecItemDelete(query(keychain) as CFDictionary)
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
