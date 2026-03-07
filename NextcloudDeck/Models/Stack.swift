import Foundation

struct Stack: Identifiable, Codable {
    let id: Int
    var title: String
    var boardId: Int
    var deletedAt: Int?
    var lastModified: Int?
    var cards: [Card]?
    var order: Int

    init(id: Int, title: String, boardId: Int, deletedAt: Int? = nil, lastModified: Int? = nil, cards: [Card]? = nil, order: Int = 999) {
        self.id = id
        self.title = title
        self.boardId = boardId
        self.deletedAt = deletedAt
        self.lastModified = lastModified
        self.cards = cards
        self.order = order
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIntOrString(forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        boardId = try c.decodeIntOrString(forKey: .boardId)
        deletedAt = try c.decodeIntOrStringIfPresent(forKey: .deletedAt)
        lastModified = try c.decodeIntOrStringIfPresent(forKey: .lastModified)
        order = try c.decodeIntOrStringIfPresent(forKey: .order) ?? 999
        if c.contains(.cards) {
            cards = (try? c.decode([Card].self, forKey: .cards)) ?? []
        } else {
            cards = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, boardId, deletedAt, lastModified, cards, order
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
