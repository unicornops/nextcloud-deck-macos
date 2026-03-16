import SwiftUI
import UniformTypeIdentifiers

private struct DraggedCard: Codable {
    let id: Int
    let stackId: Int

    var providerString: String {
        "\(id):\(stackId)"
    }

    static func fromProviderString(_ value: String) -> DraggedCard? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let id = Int(parts[0]),
              let stackId = Int(parts[1]) else {
            return nil
        }
        return DraggedCard(id: id, stackId: stackId)
    }
}

struct StackColumnView: View {
    let board: Board
    let stack: Stack
    var onSelectCard: (Card) -> Void
    var onRefresh: () -> Void
    @EnvironmentObject private var appState: AppState

    @State private var newCardTitle = ""
    @State private var isAddingCard = false
    @State private var pendingDelete = false
    @State private var pendingCardDelete: Card?
    @State private var dragInsertIndex: Int? = nil
    @State private var isColumnDropTargeted = false

    private var isDropTargeted: Bool {
        guard !appState.isDraggingStack else { return false }
        return dragInsertIndex != nil || isColumnDropTargeted
    }

    private let dropTypes = [
        UTType.plainText.identifier,
        UTType.utf8PlainText.identifier,
        UTType.text.identifier,
    ]

    private var cards: [Card] {
        (stack.cards ?? []).sorted { $0.order < $1.order }
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
                .strokeBorder(borderColor, lineWidth: isDropTargeted ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        .onDrop(of: dropTypes, isTargeted: $isColumnDropTargeted, perform: handleColumnDrop(providers:))
        .confirmationDialog("Delete list?", isPresented: $pendingDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    await appState.deleteStack(boardId: board.id, stackId: stack.id)
                    onRefresh()
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = false
            }
        } message: {
            Text("\u{201c}\(stack.title)\u{201d} and all its cards will be permanently deleted. This cannot be undone.")
        }
        .confirmationDialog("Delete card?", isPresented: Binding(
            get: { pendingCardDelete != nil },
            set: { if !$0 { pendingCardDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                guard let card = pendingCardDelete else { return }
                pendingCardDelete = nil
                Task {
                    await appState.deleteCard(boardId: board.id, stackId: stack.id, cardId: card.id)
                    onRefresh()
                }
            }
            Button("Cancel", role: .cancel) {
                pendingCardDelete = nil
            }
        } message: {
            if let card = pendingCardDelete {
                Text("\u{201c}\(card.title)\u{201d} will be permanently deleted. This cannot be undone.")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(stack.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button(role: .destructive) {
                    pendingDelete = true
                } label: {
                    Label("Delete list", systemImage: "trash")
                }
                .help("Permanently delete this list and its cards")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var cardList: some View {
        let currentCards = cards
        return ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 0) {
                insertionGap(at: 0)
                ForEach(0 ..< currentCards.count, id: \.self) { index in
                    CardRowView(card: currentCards[index], onDelete: {
                        pendingCardDelete = currentCards[index]
                    }) {
                        onSelectCard(currentCards[index])
                    }
                    .padding(.horizontal, 10)
                    insertionGap(at: index + 1)
                }
            }
            .padding(.bottom, 4)
        }
        .frame(maxHeight: .infinity)
        .background(dropTargetBackground)
    }

    @ViewBuilder
    private func insertionGap(at index: Int) -> some View {
        let targeted = dragInsertIndex == index && !appState.isDraggingStack
        ZStack(alignment: .center) {
            Color.clear
                .frame(height: targeted ? 20 : 8)
            if targeted {
                HStack(spacing: 0) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                }
                .padding(.horizontal, 10)
            }
        }
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.1), value: targeted)
        .onDrop(
            of: dropTypes,
            isTargeted: Binding(
                get: { dragInsertIndex == index },
                set: { isTargeted in
                    if isTargeted {
                        dragInsertIndex = index
                    } else if dragInsertIndex == index {
                        dragInsertIndex = nil
                    }
                }
            ),
            perform: { providers in
                handleDropAtIndex(providers: providers, insertIndex: index)
            }
        )
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
                .accessibilityLabel("Add card")
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

    private var borderColor: Color {
        if isDropTargeted {
            return .accentColor
        }
        return Color(nsColor: .separatorColor).opacity(0.5)
    }

    private var dropTargetBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.accentColor.opacity(isDropTargeted ? 0.12 : 0.001))
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
    }

    /// Picks the first matching provider from `providers`, loads its item, and
    /// parses it as a `DraggedCard`. Returns `nil` when no matching provider is
    /// found or the payload cannot be interpreted as a card.
    private func loadDraggedCard(
        from providers: [NSItemProvider],
        completion: @escaping (DraggedCard) -> Void
    )
        -> Bool {
        guard let provider = providers.first(where: { provider in
            dropTypes.contains { provider.hasItemConformingToTypeIdentifier($0) }
        }) else {
            return false
        }

        let typeIdentifier = dropTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) ?? UTType
            .plainText.identifier

        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
            let draggedCard: DraggedCard? = if let data = item as? Data, let value = String(
                data: data,
                encoding: .utf8
            ) {
                DraggedCard.fromProviderString(value)
            } else if let value = item as? String {
                DraggedCard.fromProviderString(value)
            } else if let text = item as? NSString {
                DraggedCard.fromProviderString(text as String)
            } else {
                nil
            }

            guard let draggedCard else { return }
            completion(draggedCard)
        }

        return true
    }

    private func handleDropAtIndex(providers: [NSItemProvider], insertIndex: Int) -> Bool {
        loadDraggedCard(from: providers) { draggedCard in

            Task { @MainActor in
                if draggedCard.stackId == stack.id {
                    // Reorder within the same stack
                    let currentCards = cards
                    guard let fromIndex = currentCards.firstIndex(where: { $0.id == draggedCard.id }) else { return }
                    // Adjust target: after removing the card the indices above it shift down by one
                    let targetOrder = insertIndex > fromIndex ? insertIndex - 1 : insertIndex
                    guard targetOrder != fromIndex else { return }
                    await appState.reorderCard(
                        boardId: board.id,
                        fromStackId: stack.id,
                        cardId: draggedCard.id,
                        toStackId: stack.id,
                        order: targetOrder
                    )
                } else {
                    // Move card from another stack, inserting at the specific position
                    await appState.moveCard(
                        boardId: board.id,
                        cardId: draggedCard.id,
                        fromStackId: draggedCard.stackId,
                        toStackId: stack.id,
                        order: insertIndex
                    )
                }
            }
        }
    }

    /// Fallback drop handler on the whole column — only handles cross-stack moves,
    /// appending the card to the end of this list. Gap drops take priority for
    /// precise placement (both cross-stack and within-stack reordering).
    private func handleColumnDrop(providers: [NSItemProvider]) -> Bool {
        loadDraggedCard(from: providers) { draggedCard in
            guard draggedCard.stackId != stack.id else { return }

            Task { @MainActor in
                await appState.moveCard(
                    boardId: board.id,
                    cardId: draggedCard.id,
                    fromStackId: draggedCard.stackId,
                    toStackId: stack.id,
                    order: cards.count
                )
            }
        }
    }
}

struct CardRowView: View {
    let card: Card
    var onDelete: (() -> Void)?
    var action: () -> Void
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
            if let count = card.attachmentCount, count > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "paperclip")
                        .font(.caption2)
                    Text("\(count)")
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
        .onTapGesture(perform: action)
        .onDrag {
            NSItemProvider(object: NSString(string: DraggedCard(id: card.id, stackId: card.stackId).providerString))
        }
        .onHover { hovering in
            isHovering = hovering
            DispatchQueue.main.async {
                (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
            }
        }
        .accessibilityLabel(card.title)
        .accessibilityHint("Opens card details")
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            if let onDelete {
                Button("Delete card", role: .destructive) {
                    onDelete()
                }
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
        board: Board(
            id: 1,
            title: "Test",
            color: "0082c9",
            archived: false,
            owner: nil,
            labels: [],
            acl: [],
            permissions: nil,
            users: [],
            shared: nil,
            deletedAt: nil,
            lastModified: nil,
            settings: nil
        ),
        stack: Stack(id: 1, title: "To Do", boardId: 1, deletedAt: nil, lastModified: nil, cards: [], order: 0),
        onSelectCard: { _ in },
        onRefresh: {}
    )
    .environmentObject(AppState())
}
