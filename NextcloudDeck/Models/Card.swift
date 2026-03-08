import Foundation

struct Card: Identifiable, Codable {
    let id: Int
    var title: String
    var description: String?
    var stackId: Int
    var type: String?
    var lastModified: Int?
    var createdAt: Int?
    var labels: [DeckLabel]?
    var assignedUsers: [DeckUser]?
    var attachments: [Attachment]?
    var attachmentCount: Int?
    var owner: String?
    var order: Int
    var archived: Bool
    var duedate: String?
    var deletedAt: Int?
    var commentsUnread: Int?
    var overdue: Int?
    var etag: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIntOrString(forKey: .id)) ?? 0
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? nil
        stackId = (try? c.decodeIntOrString(forKey: .stackId)) ?? 0
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? nil
        lastModified = (try? c.decodeIntOrStringIfPresent(forKey: .lastModified)) ?? nil
        createdAt = (try? c.decodeIntOrStringIfPresent(forKey: .createdAt)) ?? nil
        labels = (try? c.decodeIfPresent([DeckLabel].self, forKey: .labels)) ?? nil
        assignedUsers = (try? c.decodeIfPresent([DeckUser].self, forKey: .assignedUsers)) ?? nil
        attachments = (try? c.decodeIfPresent([Attachment].self, forKey: .attachments)) ?? nil
        attachmentCount = (try? c.decodeIntOrStringIfPresent(forKey: .attachmentCount)) ?? nil
        owner = (try? c.decodeIfPresent(String.self, forKey: .owner)) ?? nil
        order = (try? c.decodeIntOrStringIfPresent(forKey: .order)) ?? 999
        archived = (try? c.decodeIfPresent(Bool.self, forKey: .archived)) ?? false
        duedate = (try? c.decodeIfPresent(String.self, forKey: .duedate)) ?? nil
        deletedAt = (try? c.decodeIntOrStringIfPresent(forKey: .deletedAt)) ?? nil
        commentsUnread = (try? c.decodeIntOrStringIfPresent(forKey: .commentsUnread)) ?? nil
        overdue = (try? c.decodeIntOrStringIfPresent(forKey: .overdue)) ?? nil
        etag = (try? c.decodeIfPresent(String.self, forKey: .etag)) ?? nil
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, stackId, type, lastModified, createdAt
        case labels, assignedUsers, attachments, attachmentCount, owner, order
        case archived, duedate, deletedAt, commentsUnread, overdue
        case etag = "ETag"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(description ?? "", forKey: .description)
        try c.encode(stackId, forKey: .stackId)
        try c.encode(type ?? "plain", forKey: .type)
        try c.encodeIfPresent(lastModified, forKey: .lastModified)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encode(labels ?? [], forKey: .labels)
        try c.encode(assignedUsers ?? [], forKey: .assignedUsers)
        try c.encodeIfPresent(attachments, forKey: .attachments)
        try c.encode(attachmentCount ?? 0, forKey: .attachmentCount)
        try c.encodeIfPresent(owner, forKey: .owner)
        try c.encode(order, forKey: .order)
        try c.encode(archived, forKey: .archived)
        try c.encodeIfPresent(duedate, forKey: .duedate)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try c.encode(commentsUnread ?? 0, forKey: .commentsUnread)
        try c.encodeIfPresent(overdue, forKey: .overdue)
        try c.encodeIfPresent(etag, forKey: .etag)
    }
}

private extension KeyedDecodingContainer {
    func decodeIntOrString(forKey key: Key) throws -> Int {
        if let i = try? decode(Int.self, forKey: key) { return i }
        if let s = try? decode(String.self, forKey: key), let i = Int(s) { return i }
        throw DecodingError.typeMismatch(Int.self, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Expected Int or String"))
    }
    func decodeIntOrStringIfPresent(forKey key: Key) throws -> Int? {
        if let i = try? decode(Int.self, forKey: key) { return i }
        if let s = try? decode(String.self, forKey: key), let i = Int(s) { return i }
        return nil
    }
}

struct Attachment: Codable, Identifiable {
    let id: Int
    var cardId: Int?
    var type: String?
    var data: String?
    var lastModified: Int?
    var createdAt: Int?
    var createdBy: String?
    var deletedAt: Int?
    var extendedData: AttachmentExtendedData?

    enum CodingKeys: String, CodingKey {
        case id, cardId, type, data, lastModified, createdAt, createdBy, deletedAt, extendedData
    }
}

struct AttachmentExtendedData: Codable {
    var filesize: Int?
    var mimetype: String?
    var info: AttachmentInfo?
}

struct AttachmentInfo: Codable {
    var dirname: String?
    var basename: String?
    var fileExtension: String?
    var filename: String?

    enum CodingKeys: String, CodingKey {
        case dirname, basename, filename
        case fileExtension = "extension"
    }
}
