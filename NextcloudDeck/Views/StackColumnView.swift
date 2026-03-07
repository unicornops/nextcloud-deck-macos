import SwiftUI

struct StackColumnView: View {
    let board: Board
    let stack: Stack
    var onSelectCard: (Card) -> Void
    var onRefresh: () -> Void
    @EnvironmentObject private var appState: AppState
    
    @State private var newCardTitle = ""
    @State private var isAddingCard = false
    
    private var cards: [Card] {
        stack.cards ?? []
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            cardList
            addCardField
        }
        .frame(width: 280)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        )
    }
    
    private var header: some View {
        Text(stack.title)
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
    }
    
    private var cardList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 8) {
                ForEach(cards) { card in
                    CardRowView(card: card)
                        .onTapGesture { onSelectCard(card) }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .frame(maxHeight: .infinity)
    }
    
    private var addCardField: some View {
        Group {
            if isAddingCard {
                HStack(spacing: 8) {
                    TextField("Card title", text: $newCardTitle)
                        .textFieldStyle(.plain)
                        .onSubmit { submitNewCard() }
                    Button("Add") { submitNewCard() }
                        .buttonStyle(.borderedProminent)
                    Button("Cancel") {
                        isAddingCard = false
                        newCardTitle = ""
                    }
                }
                .padding(10)
            } else {
                Button {
                    isAddingCard = true
                } label: {
                    SwiftUI.Label("Add card", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(10)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(10)
    }
    
    private func submitNewCard() {
        let title = newCardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newCardTitle = ""
        isAddingCard = false
        Task {
            await appState.createCard(boardId: board.id, stackId: stack.id, title: title)
            onRefresh()
        }
    }
}

struct CardRowView: View {
    let card: Card
    @State private var isHovering = false

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.title)
                .font(.system(.body, design: .default))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let due = card.duedate, !due.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(formatDueDate(due))
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            if let labels = card.labels, !labels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(labels.prefix(3)) { label in
                        Text(label.title)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: label.color ?? "cccccc") ?? .gray.opacity(0.3))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            (isHovering ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .windowBackgroundColor))
                .opacity(isHovering ? 1.0 : 0.98)
        )
        .clipShape(cardShape)
        .overlay(
            cardShape
                .strokeBorder(
                    Color(nsColor: .separatorColor).opacity(isHovering ? 0.6 : 0.4),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(isHovering ? 0.08 : 0.05), radius: isHovering ? 4 : 2, y: 2)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            DispatchQueue.main.async {
                (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
            }
        }
    }
    
    private func formatDueDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let f = DateFormatter()
            f.dateStyle = .short
            return f.string(from: date)
        }
        return iso
    }
}

#Preview {
    StackColumnView(
        board: Board(id: 1, title: "Test", color: "0082c9", archived: false, owner: nil, labels: [], acl: [], permissions: nil, users: [], shared: nil, deletedAt: nil, lastModified: nil, settings: nil),
        stack: Stack(id: 1, title: "To Do", boardId: 1, deletedAt: nil, lastModified: nil, cards: [], order: 0),
        onSelectCard: { _ in },
        onRefresh: { }
    )
    .environmentObject(AppState())
}
