import Foundation

// MARK: - Account

/// A signed-in Nextcloud account: who and on which server. The app password is only in `Credentials`.
struct Account: Hashable, Identifiable, Sendable {
    let serverURL: URL
    let username: String

    /// The server as shown in the account menu: its host plus any path, e.g. `cloud.example/nextcloud`.
    var serverName: String {
        let host = serverURL.host?.lowercased() ?? serverURL.absoluteString
        let port = serverURL.port.map { ":\($0)" } ?? ""
        var path = serverURL.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        return host + port + path
    }

    /// One account per user per server: signing in to the same one again replaces its app password.
    var id: String {
        "\(username)@\(serverName)"
    }
}

// MARK: - Credentials

/// An account and the app password the app signs in with.
struct Credentials: Codable, Hashable, Sendable {
    let serverURL: URL
    let username: String
    let appPassword: String

    /// Always stores an HTTPS server URL.
    init(serverURL: URL, username: String, appPassword: String) {
        self.serverURL = Self.httpsURL(from: serverURL)
        self.username = username
        self.appPassword = appPassword
    }

    var account: Account {
        Account(serverURL: serverURL, username: username)
    }

    private static func httpsURL(from url: URL) -> URL {
        guard url.scheme == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = "https"
        return components.url ?? url
    }
}

// MARK: - SavedAccounts

/// Every signed-in account and which one is in use, kept together in the Keychain.
///
/// Decodes the single-account format of earlier versions too, so upgrading keeps the user signed in.
struct SavedAccounts: Codable, Equatable, Sendable {
    private(set) var all: [Credentials] = []
    private(set) var activeId: String?

    init() {}

    /// The account in use: the one last chosen, or the first if that one is gone.
    var active: Credentials? {
        all.first { $0.account.id == activeId } ?? all.first
    }

    var accounts: [Account] {
        all.map(\.account)
    }

    func credentials(for id: Account.ID) -> Credentials? {
        all.first { $0.account.id == id }
    }

    /// Adds `credentials` and makes them active. Returns the credentials they replace when that account was
    /// already signed in, so the old app password can be revoked.
    @discardableResult
    mutating func add(_ credentials: Credentials) -> Credentials? {
        let id = credentials.account.id
        activeId = id
        if let index = all.firstIndex(where: { $0.account.id == id }) {
            let replaced = all[index]
            all[index] = credentials
            return replaced
        }
        all.append(credentials)
        return nil
    }

    /// Makes the account with `id` active, if it is signed in.
    mutating func activate(_ id: Account.ID) {
        guard credentials(for: id) != nil else { return }
        activeId = id
    }

    /// Forgets the account with `id`; if it was active, the first remaining account becomes active.
    mutating func remove(_ id: Account.ID) {
        all.removeAll { $0.account.id == id }
        if activeId == id {
            activeId = all.first?.account.id
        }
    }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case accounts, activeId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.accounts) {
            self.all = try container.decode([Credentials].self, forKey: .accounts)
            self.activeId = try container.decodeIfPresent(String.self, forKey: .activeId)
        } else {
            // Earlier versions stored one account's credentials on their own.
            let single = try Credentials(from: decoder)
            self.all = [single]
            self.activeId = single.account.id
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(all, forKey: .accounts)
        try container.encodeIfPresent(activeId, forKey: .activeId)
    }
}
