import SwiftUI

// MARK: - ArchivedCardsSheet

/// The board's archived cards, grouped by list, each with an Unarchive button.
struct ArchivedCardsSheet: View {
    let board: Board
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var stacks: [Stack]?
    @State private var unarchiving: Set<Int> = []

    private var stacksWithArchivedCards: [Stack] {
        (stacks ?? []).filter { !$0.archivedCards.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Archived Cards")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()
            content
        }
        .frame(width: 440, height: 480)
        .actionErrorBanner(appState)
        .task {
            stacks = await appState.archivedStacks(boardId: board.id)
        }
    }

    @ViewBuilder
    private var content: some View {
        if stacks == nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if stacksWithArchivedCards.isEmpty {
            ContentUnavailableView(
                "No Archived Cards",
                systemImage: "archivebox",
                description: Text("Cards you archive on \(board.title) appear here.")
            )
        } else {
            List {
                ForEach(stacksWithArchivedCards) { stack in
                    Section(stack.title) {
                        ForEach(stack.archivedCards) { card in
                            row(card)
                        }
                    }
                }
            }
        }
    }

    private func row(_ card: Card) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                if let dueDate = card.dueDate {
                    Text(dueDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Unarchive") {
                Task { await unarchive(card) }
            }
            .disabled(unarchiving.contains(card.id))
            .accessibilityLabel("Unarchive \(card.title)")
        }
    }

    private func unarchive(_ card: Card) async {
        unarchiving.insert(card.id)
        defer { unarchiving.remove(card.id) }
        guard await appState.unarchiveCard(card, boardId: board.id), let current = stacks else { return }
        // Drop it from this sheet; the board's lists were reloaded with the card back in place.
        stacks = current.map { stack in
            var stack = stack
            stack.cards = stack.cards?.filter { $0.id != card.id }
            return stack
        }
    }
}
