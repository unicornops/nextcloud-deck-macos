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
    var startdate: String?
    /// ISO-8601 date the card was marked done, or nil when not done.
    var done: String?
    var deletedAt: Int?
    var commentsUnread: Int?
    var overdue: Int?
    var etag: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decodeIntOrString(forKey: .id)) ?? 0
        self.title = (try? c.decode(String.self, forKey: .title)) ?? ""
        self.description = (try? c.decodeIfPresent(String.self, forKey: .description))
        self.stackId = (try? c.decodeIntOrString(forKey: .stackId)) ?? 0
        self.type = (try? c.decodeIfPresent(String.self, forKey: .type))
        self.lastModified = (try? c.decodeIntOrStringIfPresent(forKey: .lastModified))
        self.createdAt = (try? c.decodeIntOrStringIfPresent(forKey: .createdAt))
        self.labels = (try? c.decodeIfPresent([DeckLabel].self, forKey: .labels))
        self.assignedUsers = (try? c.decodeIfPresent([DeckUser].self, forKey: .assignedUsers))
        self.attachments = (try? c.decodeIfPresent([Attachment].self, forKey: .attachments))
        self.attachmentCount = (try? c.decodeIntOrStringIfPresent(forKey: .attachmentCount))
        // Deck serialises the owner as a user object; older responses used the plain user id.
        self.owner = (try? c.decodeIfPresent(String.self, forKey: .owner))
            ?? (try? c.decodeIfPresent(DeckUser.self, forKey: .owner))?.uid
        self.order = (try? c.decodeIntOrStringIfPresent(forKey: .order)) ?? 999
        self.archived = (try? c.decodeIfPresent(Bool.self, forKey: .archived)) ?? false
        self.duedate = (try? c.decodeIfPresent(String.self, forKey: .duedate))
        self.startdate = (try? c.decodeIfPresent(String.self, forKey: .startdate))
        self.done = (try? c.decodeIfPresent(String.self, forKey: .done))
        self.deletedAt = (try? c.decodeIntOrStringIfPresent(forKey: .deletedAt))
        self.commentsUnread = (try? c.decodeIntOrStringIfPresent(forKey: .commentsUnread))
        self.overdue = (try? c.decodeIntOrStringIfPresent(forKey: .overdue))
        self.etag = (try? c.decodeIfPresent(String.self, forKey: .etag))
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, stackId, type, lastModified, createdAt
        case labels, assignedUsers, attachments, attachmentCount, owner, order
        case archived, duedate, startdate, done, deletedAt, commentsUnread, overdue
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
        try c.encodeIfPresent(startdate, forKey: .startdate)
        try c.encodeIfPresent(done, forKey: .done)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try c.encode(commentsUnread ?? 0, forKey: .commentsUnread)
        try c.encodeIfPresent(overdue, forKey: .overdue)
        try c.encodeIfPresent(etag, forKey: .etag)
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decodeIntOrString(forKey: .id)) ?? 0
        self.cardId = try? c.decodeIntOrStringIfPresent(forKey: .cardId)
        self.type = (try? c.decodeIfPresent(String.self, forKey: .type))
        self.data = (try? c.decodeIfPresent(String.self, forKey: .data))
            ?? (try? c.decodeIfPresent(Int.self, forKey: .data)).map { String($0) }
        self.lastModified = try? c.decodeIntOrStringIfPresent(forKey: .lastModified)
        self.createdAt = try? c.decodeIntOrStringIfPresent(forKey: .createdAt)
        self.createdBy = (try? c.decodeIfPresent(String.self, forKey: .createdBy))
        self.deletedAt = try? c.decodeIntOrStringIfPresent(forKey: .deletedAt)
        self.extendedData = try? c.decodeIfPresent(AttachmentExtendedData.self, forKey: .extendedData)
    }

    /// Display name for the attachment (filename).
    var displayName: String {
        extendedData?.info?.basename ?? extendedData?.info?.filename ?? data ?? "Attachment \(id)"
    }

    /// Human-readable file size.
    var formattedSize: String? {
        guard let bytes = extendedData?.filesize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
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
