import Foundation

struct Stack: Identifiable, Codable {
    let id: Int
    var title: String
    var boardId: Int
    var deletedAt: Int?
    var lastModified: Int?
    var cards: [Card]?
    var order: Int

    init(
        id: Int,
        title: String,
        boardId: Int,
        deletedAt: Int? = nil,
        lastModified: Int? = nil,
        cards: [Card]? = nil,
        order: Int = 999
    ) {
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
        self.id = try c.decodeIntOrString(forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.boardId = try c.decodeIntOrString(forKey: .boardId)
        self.deletedAt = try c.decodeIntOrStringIfPresent(forKey: .deletedAt)
        self.lastModified = try c.decodeIntOrStringIfPresent(forKey: .lastModified)
        self.order = try c.decodeIntOrStringIfPresent(forKey: .order) ?? 999
        if c.contains(.cards) {
            var decoded = (try? c.decode([Card].self, forKey: .cards)) ?? []
            // Ensure each card has the correct stackId (some Deck servers omit it
            // from the nested card objects since it is implicit from the parent stack).
            for i in decoded.indices where decoded[i].stackId == 0 {
                decoded[i].stackId = id
            }
            self.cards = decoded
        } else {
            self.cards = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, boardId, deletedAt, lastModified, cards, order
    }
}

extension Stack {
    /// The stack's cards that aren't archived, in board order.
    var activeCards: [Card] {
        (cards ?? []).filter { !$0.archived }.sorted { $0.order < $1.order }
    }

    /// The stack's archived cards, most recently changed first.
    var archivedCards: [Card] {
        (cards ?? []).filter(\.archived).sorted { ($0.lastModified ?? 0) > ($1.lastModified ?? 0) }
    }
}
