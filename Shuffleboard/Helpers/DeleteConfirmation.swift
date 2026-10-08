import Foundation

// MARK: - DeleteConfirmation

/// Wording for delete confirmations.
///
/// Deck soft-deletes boards, lists and cards: they can be restored until the server's cleanup job removes them,
/// after its trash retention (`trashRetentionHours`, 5 hours by default). Boards can be restored from "Recently
/// Deleted" in the sidebar; lists and cards from Deck in the browser.
enum DeleteConfirmation {
    private static let untilCleared = "until the server clears deleted items (after 5 hours by default)."
    static let restoreNote = "You can restore it from Deck in your browser " + untilCleared
    static let boardRestoreNote = "You can restore it from Recently Deleted in the sidebar " + untilCleared

    /// "<subject> will be deleted." followed by how to restore it.
    static func message(_ subject: String, restoreNote: String = Self.restoreNote) -> String {
        "\(subject) will be deleted. \(restoreNote)"
    }
}
