import Foundation

/// A direction on the board: up and down within a list, left and right between lists.
enum CardDirection: Sendable {
    case up
    case down
    case left
    case right
}

extension [Stack] {
    /// The card the selection moves to from card `cardId` in `direction`, among the cards each list shows
    /// (`shown`); nil if it can't move that way. With no card selected, or one that isn't shown, it's the first
    /// card on the board. Moving left or right skips lists with no cards and keeps the position in the list as
    /// far as the next list allows.
    func cardId(from cardId: Int?, moving direction: CardDirection, shown: (Stack) -> [Card]) -> Int? {
        let columns = map(shown)
        guard let cardId,
              let column = columns.firstIndex(where: { $0.contains { $0.id == cardId } }),
              let row = columns[column].firstIndex(where: { $0.id == cardId }) else {
            return columns.first { !$0.isEmpty }?.first?.id
        }
        switch direction {
        case .up:
            return row > 0 ? columns[column][row - 1].id : nil

        case .down:
            return row < columns[column].count - 1 ? columns[column][row + 1].id : nil

        case .left, .right:
            let step = direction == .left ? -1 : 1
            var next = column + step
            while columns.indices.contains(next) {
                if let card = columns[next].isEmpty ? nil : columns[next][Swift.min(row, columns[next].count - 1)] {
                    return card.id
                }
                next += step
            }
            return nil
        }
    }

    /// Where card `cardId` goes when moved one step in `direction`: the list and its position among that list's
    /// active cards, as `AppState.reorderCard` takes them. Up and down stay in the list; left and right go to the
    /// next list, even an empty one, keeping the position as far as it can. Nil at the edge of the board.
    func destination(movingCard cardId: Int, _ direction: CardDirection) -> (stackId: Int, order: Int)? {
        guard let column = firstIndex(where: { $0.activeCards.contains { $0.id == cardId } }),
              let row = self[column].activeCards.firstIndex(where: { $0.id == cardId }) else { return nil }
        let count = self[column].activeCards.count
        switch direction {
        case .up:
            return row > 0 ? (self[column].id, row - 1) : nil

        case .down:
            return row < count - 1 ? (self[column].id, row + 1) : nil

        case .left, .right:
            let next = column + (direction == .left ? -1 : 1)
            guard indices.contains(next) else { return nil }
            return (self[next].id, Swift.min(row, self[next].activeCards.count))
        }
    }
}
