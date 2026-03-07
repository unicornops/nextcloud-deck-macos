import Foundation
import Security

/// Stores and retrieves Nextcloud credentials in the system Keychain.
final class KeychainStorage {
    private static let service = "com.nextcloud.deck.macos"
    private static let serverKey = "serverURL"
    private static let userKey = "username"
    private static let appPasswordKey = "appPassword"
    
    static func save(serverURL: URL, username: String, appPassword: String) throws {
        let server = serverURL.absoluteString
        try delete()
        let items: [(String, String)] = [(serverKey, server), (userKey, username), (appPasswordKey, appPassword)]
        for (key, value) in items {
            guard let data = value.data(using: .utf8) else { continue }
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
        }
    }
    
    static func load() -> (serverURL: URL, username: String, appPassword: String)? {
        guard let server = get(serverKey),
              let username = get(userKey),
              let appPassword = get(appPasswordKey),
              let url = URL(string: server) else { return nil }
        return (url, username, appPassword)
    }
    
    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    static var isLoggedIn: Bool { load() != nil }
    
    private static func get(_ account: String) -> String? {
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
