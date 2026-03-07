import Foundation

struct Board: Identifiable, Codable, Hashable {
    let id: Int
    var title: String
    var color: String?
    var archived: Bool
    var owner: DeckUser?
    var labels: [DeckLabel]
    var acl: [ACLEntry]
    var permissions: BoardPermissions?
    var users: [DeckUser]
    var shared: Int?
    var deletedAt: Int?
    var lastModified: Int?
    var settings: BoardSettings?

    init(id: Int, title: String, color: String? = nil, archived: Bool = false, owner: DeckUser? = nil, labels: [DeckLabel] = [], acl: [ACLEntry] = [], permissions: BoardPermissions? = nil, users: [DeckUser] = [], shared: Int? = nil, deletedAt: Int? = nil, lastModified: Int? = nil, settings: BoardSettings? = nil) {
        self.id = id
        self.title = title
        self.color = color
        self.archived = archived
        self.owner = owner
        self.labels = labels
        self.acl = acl
        self.permissions = permissions
        self.users = users
        self.shared = shared
        self.deletedAt = deletedAt
        self.lastModified = lastModified
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIntOrString(forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        owner = try c.decodeIfPresent(DeckUser.self, forKey: .owner)
        labels = try c.decodeIfPresent([DeckLabel].self, forKey: .labels) ?? []
        acl = try c.decodeIfPresent([ACLEntry].self, forKey: .acl) ?? []
        permissions = try c.decodeIfPresent(BoardPermissions.self, forKey: .permissions)
        users = try c.decodeIfPresent([DeckUser].self, forKey: .users) ?? []
        shared = try c.decodeIfPresent(Int.self, forKey: .shared)
        deletedAt = try c.decodeIfPresent(Int.self, forKey: .deletedAt)
        lastModified = try c.decodeIfPresent(Int.self, forKey: .lastModified)
        settings = try c.decodeIfPresent(BoardSettings.self, forKey: .settings)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, color, archived, owner, labels, acl, permissions, users, shared, deletedAt, lastModified, settings
    }
}

private extension KeyedDecodingContainer {
    func decodeIntOrString(forKey key: Key) throws -> Int {
        if let i = try? decode(Int.self, forKey: key) { return i }
        if let s = try? decode(String.self, forKey: key), let i = Int(s) { return i }
        throw DecodingError.typeMismatch(Int.self, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Expected Int or String"))
    }
}

struct BoardPermissions: Codable, Hashable {
    let permissionRead: Bool
    let permissionEdit: Bool
    let permissionManage: Bool
    let permissionShare: Bool
    
    enum CodingKeys: String, CodingKey {
        case permissionRead = "PERMISSION_READ"
        case permissionEdit = "PERMISSION_EDIT"
        case permissionManage = "PERMISSION_MANAGE"
        case permissionShare = "PERMISSION_SHARE"
    }
}

struct BoardSettings: Codable, Hashable {
    var notifyDue: String?
    var calendar: Bool?
    
    enum CodingKeys: String, CodingKey {
        case notifyDue = "notify-due"
        case calendar
    }
}

struct ACLEntry: Codable, Hashable {
    let id: Int?
    let participant: DeckUser?
    let type: Int
    let boardId: Int?
    var permissionEdit: Bool
    var permissionShare: Bool
    var permissionManage: Bool
    var owner: Bool?
}

struct DeckUser: Codable, Hashable {
    let primaryKey: String?
    let uid: String
    let displayname: String?

    init(primaryKey: String? = nil, uid: String = "", displayname: String? = nil) {
        self.primaryKey = primaryKey
        self.uid = uid
        self.displayname = displayname
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primaryKey = try c.decodeIfPresent(String.self, forKey: .primaryKey)
        uid = try c.decodeIfPresent(String.self, forKey: .uid) ?? ""
        displayname = try c.decodeIfPresent(String.self, forKey: .displayname)
    }

    enum CodingKeys: String, CodingKey {
        case primaryKey, uid, displayname
    }
}
