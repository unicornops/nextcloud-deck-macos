import Foundation

// MARK: - DeleteConfirmation

/// Wording for delete confirmations.
///
/// Deck soft-deletes boards, lists and cards: they can be restored from Deck in the browser until the
/// server's cleanup job removes them, after its trash retention (`trashRetentionHours`, 5 hours by default).
enum DeleteConfirmation {
    static let restoreNote = "You can restore it from Deck in your browser until the server clears deleted items "
        + "(after 5 hours by default)."

    /// "<subject> will be deleted." followed by how to restore it.
    static func message(_ subject: String) -> String {
        "\(subject) will be deleted. \(restoreNote)"
    }
}
