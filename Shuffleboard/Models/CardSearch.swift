import Foundation

/// A card found by searching all boards (#158).
struct CardSearchResult: Identifiable {
    let boardId: Int
    let listTitle: String
    let card: Card

    var id: String {
        "\(boardId)-\(card.id)"
    }
}

/// One board's search results.
struct BoardSearchResults: Identifiable {
    let board: Board
    let results: [CardSearchResult]

    var id: Int {
        board.id
    }
}

/// A board's cards to search: its lists with their active cards, and its lists with their archived cards.
struct SearchableCards {
    var stacks: [Stack] = []
    var archivedStacks: [Stack] = []
}

/// Searching every board's cards in the app, on the lists Deck's REST API returns (#158). Deck's documented API has
/// no search; Nextcloud's unified search finds cards, but only gives a web link to each, not its board or list.
enum CardSearch {
    /// The query's words; a card matches if it has all of them.
    static func words(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Whether every word is in the card's title, description, labels or assignees' names, ignoring case and
    /// accents.
    static func matches(_ card: Card, words: [String]) -> Bool {
        guard !words.isEmpty else { return false }
        let fields = [card.title, card.description ?? ""]
            + (card.labels ?? []).map(\.title)
            + card.assignments.map(\.participant.displayName)
        return words.allSatisfy { word in
            fields.contains { $0.localizedStandardContains(word) }
        }
    }

    /// The cards matching `query`, grouped by board in `boards`' order, leaving out boards with none. Within a
    /// board, active cards come first in board order, then archived ones.
    static func results(
        for query: String,
        in boards: [Board],
        cards: (Board) -> SearchableCards
    )
        -> [BoardSearchResults] {
        let words = words(in: query)
        guard !words.isEmpty else { return [] }
        return boards.compactMap { board in
            let searchable = cards(board)
            let active = AppState.sorted(searchable.stacks).flatMap { stack in
                stack.activeCards.map { (stack.title, $0) }
            }
            let archived = AppState.sorted(searchable.archivedStacks).flatMap { stack in
                stack.archivedCards.map { (stack.title, $0) }
            }
            let results = (active + archived)
                .filter { matches($0.1, words: words) }
                .map { CardSearchResult(boardId: board.id, listTitle: $0.0, card: $0.1) }
            return results.isEmpty ? nil : BoardSearchResults(board: board, results: results)
        }
    }
}
