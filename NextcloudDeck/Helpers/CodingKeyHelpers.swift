import Foundation

// MARK: - KeyedDecodingContainer helpers

/// Shared decoding helpers used by all Deck model types (Board, Card, Stack, Label).
///
/// The Nextcloud Deck API inconsistently returns numeric identifiers as either JSON
/// numbers or JSON strings depending on the server version and endpoint. These helpers
/// absorb that inconsistency so each model's `init(from:)` does not need to duplicate
/// the fallback logic.
///
/// **Usage**
/// ```swift
/// self.id = try c.decodeIntOrString(forKey: .id)
/// self.order = try c.decodeIntOrStringIfPresent(forKey: .order) ?? 999
/// ```
///
/// **Source of truth**
/// This extension is the single definition. The private copies that previously lived
/// at the bottom of `Board.swift`, `Card.swift`, `Stack.swift`, and `Label.swift`
/// have been removed; those files now rely on this one.
extension KeyedDecodingContainer {
    // MARK: - Required integer (Int or String-encoded Int)

    /// Decodes an `Int` for `key`, accepting either a JSON number or a JSON string
    /// whose content parses as a base-10 integer.
    ///
    /// Throws `DecodingError.typeMismatch` if neither representation succeeds.
    func decodeIntOrString(forKey key: Key) throws -> Int {
        if let i = try? decode(Int.self, forKey: key) { return i }
        if let s = try? decode(String.self, forKey: key), let i = Int(s) { return i }
        throw DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected Int or String-encoded Int"
            )
        )
    }

    // MARK: - Optional integer (Int or String-encoded Int)

    /// Decodes an `Int?` for `key` when the field may be absent or null,
    /// accepting either a JSON number or a JSON string whose content parses
    /// as a base-10 integer.
    ///
    /// Returns `nil` when the key is missing, the value is `null`, or the
    /// value cannot be interpreted as an integer — never throws.
    func decodeIntOrStringIfPresent(forKey key: Key) throws -> Int? {
        if let i = try? decode(Int.self, forKey: key) { return i }
        if let s = try? decode(String.self, forKey: key), let i = Int(s) { return i }
        return nil
    }
}
