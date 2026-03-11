import Foundation

struct DeckLabel: Identifiable, Codable, Hashable {
    let id: Int
    var title: String
    var color: String?
    var boardId: Int?
    var cardId: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decodeIntOrString(forKey: .id)) ?? 0
        self.title = (try? c.decode(String.self, forKey: .title)) ?? ""
        self.color = (try? c.decodeIfPresent(String.self, forKey: .color)) ?? nil
        self.boardId = (try? c.decodeIntOrStringIfPresent(forKey: .boardId)) ?? nil
        self.cardId = (try? c.decodeIntOrStringIfPresent(forKey: .cardId)) ?? nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(color, forKey: .color)
        try c.encode(boardId, forKey: .boardId)
        try c.encode(cardId, forKey: .cardId)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, color, boardId, cardId
    }
}

private extension KeyedDecodingContainer {
    func decodeIntOrString(forKey key: Key) throws -> Int {
        if let i = try? decode(Int.self, forKey: key) { return i }
        if let s = try? decode(String.self, forKey: key), let i = Int(s) { return i }
        throw DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Expected Int or String")
        )
    }

    func decodeIntOrStringIfPresent(forKey key: Key) throws -> Int? {
        if let i = try? decode(Int.self, forKey: key) { return i }
        if let s = try? decode(String.self, forKey: key), let i = Int(s) { return i }
        return nil
    }
}
