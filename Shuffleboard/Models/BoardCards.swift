import Foundation

/// A board's cards as last fetched, for searching all boards (#158) without fetching every board each time.
struct BoardCards {
    /// The board's lists with their active cards.
    var stacks: [Stack]
    /// The board's lists with their archived cards; nil until something asks for them.
    var archivedStacks: [Stack]?
    /// The board's `lastModified` when these were fetched. Deck updates it whenever anything on the board changes.
    var lastModified: Int?
    /// When the board list first reported that `lastModified`.
    var lastModifiedSeen: Date
    /// When the fetch of these started.
    var fetched: Date

    /// Whether these are still `board`'s cards: its `lastModified` is the same, and they were fetched comfortably
    /// after it was first reported. Deck counts `lastModified` in whole seconds, so a fetch in the same second as a
    /// change could have missed a second change in that second.
    func isCurrent(for board: Board) -> Bool {
        lastModified != nil && lastModified == board.lastModified && fetched.timeIntervalSince(lastModifiedSeen) >= 1.5
    }
}
