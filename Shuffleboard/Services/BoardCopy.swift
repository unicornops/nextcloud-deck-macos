import Foundation

// MARK: - Copying boards

/// What `DeckAPI.copyBoard` makes.
struct BoardCopyOptions: Equatable, Sendable {
    var title: String
    /// Also copy each list's cards (not archived ones), with their descriptions, dates, done state and labels.
    var withCards: Bool
}

extension DeckAPI {
    /// Duplicates a board with documented API calls only (Deck's own clone is an internal route of its web UI): creates
    /// a board with the source's colour, makes its labels match the source's, then recreates the lists and, with
    /// `withCards`, their cards. Comments, attachments, assignments, sharing and archived cards aren't copied.
    ///
    /// If a step fails, the half-made copy is deleted and the error rethrown. `progress` is told how many of the lists
    /// and cards are done.
    func copyBoard(
        _ source: Board,
        options: BoardCopyOptions,
        progress: @escaping @Sendable @MainActor (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) async throws
        -> Board {
        let lists = try await getStacks(boardId: source.id).sorted { ($0.order, $0.id) < ($1.order, $1.id) }
        let labels = try await getBoard(id: source.id).labels
        let total = lists.count + (options.withCards ? lists.reduce(0) { $0 + $1.activeCards.count } : 0)
        let copy = try await createBoard(title: options.title, color: source.color ?? "0082c9")
        do {
            let labelIds = try await matchLabels(of: copy.id, to: labels)
            var done = 0
            for (index, list) in lists.enumerated() {
                let newList = try await createStack(boardId: copy.id, title: list.title, order: index)
                done += 1
                await progress(done, total)
                guard options.withCards else { continue }
                for (order, card) in list.activeCards.enumerated() {
                    try await copyCard(card, toBoard: copy.id, stack: newList.id, order: order, labelIds: labelIds)
                    done += 1
                    await progress(done, total)
                }
            }
            return try await getBoard(id: copy.id)
        } catch {
            try? await deleteBoard(id: copy.id)
            throw error
        }
    }

    /// Makes the new board's labels the source's: Deck gives a new board default labels, so ones with a source
    /// label's title are kept (and recoloured), the rest deleted, and missing ones created. Returns source label id →
    /// copy's label id.
    private func matchLabels(of boardId: Int, to source: [DeckLabel]) async throws -> [Int: Int] {
        var defaults = try await getBoard(id: boardId).labels
        var ids: [Int: Int] = [:]
        for label in source {
            let color = label.color ?? "31CC7C"
            if let index = defaults.firstIndex(where: { $0.title == label.title }) {
                let existing = defaults.remove(at: index)
                if existing.color?.lowercased() != color.lowercased() {
                    _ = try await updateLabel(boardId: boardId, labelId: existing.id, title: label.title, color: color)
                }
                ids[label.id] = existing.id
            } else {
                ids[label.id] = try await createLabel(boardId: boardId, title: label.title, color: color).id
            }
        }
        for unused in defaults {
            try await deleteLabel(boardId: boardId, labelId: unused.id)
        }
        return ids
    }

    private func copyCard(
        _ card: Card,
        toBoard boardId: Int,
        stack: Int,
        order: Int,
        labelIds: [Int: Int]
    ) async throws {
        var created = try await createCard(
            boardId: boardId,
            stackId: stack,
            title: card.title,
            description: card.description,
            order: order,
            duedate: card.duedate
        )
        // Creating a card doesn't take a start date or done state.
        if card.startdate != nil || card.done != nil {
            created.startdate = card.startdate
            created.done = card.done
            created.duedate = card.duedate
            created.description = card.description
            _ = try await updateCard(boardId: boardId, stackId: stack, card: created)
        }
        for label in card.labels ?? [] {
            guard let id = labelIds[label.id] else { continue }
            try await assignLabel(boardId: boardId, stackId: stack, cardId: created.id, labelId: id)
        }
    }
}
