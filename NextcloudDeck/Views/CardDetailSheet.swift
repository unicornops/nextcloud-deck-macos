import SwiftUI

struct CardDetailSheet: View {
    let card: Card
    let boardId: Int
    var onDismiss: () -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String
    @State private var description: String
    @State private var isSaving = false
    @State private var showDeleteConfirmation = false
    @State private var showCreateLabel = false
    @State private var newLabelTitle = ""
    @State private var newLabelColor = "31CC7C"
    @State private var isCreatingLabel = false
    
    private var board: Board? {
        guard let b = appState.selectedBoard, b.id == boardId else { return nil }
        return b
    }
    
    /// Latest card from stacks so label assign/remove updates in the sheet.
    private var currentCard: Card? {
        guard let stack = appState.stacks.first(where: { $0.id == card.stackId }) else { return nil }
        return stack.cards?.first(where: { $0.id == card.id })
    }
    
    private var cardLabels: [DeckLabel] {
        (currentCard ?? card).labels ?? []
    }
    
    private var availableBoardLabels: [DeckLabel] {
        guard let board = board else { return [] }
        let assignedIds = Set(cardLabels.map(\.id))
        return board.labels.filter { !assignedIds.contains($0.id) }
    }
    
    init(card: Card, boardId: Int, onDismiss: @escaping () -> Void) {
        self.card = card
        self.boardId = boardId
        self.onDismiss = onDismiss
        _title = State(initialValue: card.title)
        _description = State(initialValue: card.description ?? "")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") {
                    dismiss()
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(minWidth: 44)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isSaving || title.isEmpty)
            }
            .padding()
            Divider()
            
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }
                Section("Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 120)
                        .font(.body)
                }
                Section("Labels") {
                    labelsContent
                }
                Section {
                    Button("Delete card", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 440, height: 420)
        .navigationTitle("Edit Card")
        .sheet(isPresented: $showCreateLabel) {
            createLabelSheet
        }
        .confirmationDialog("Delete card?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await appState.deleteCard(boardId: boardId, stackId: card.stackId, cardId: card.id)
                    await MainActor.run {
                        dismiss()
                        onDismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                showDeleteConfirmation = false
            }
        } message: {
            Text("This card will be permanently deleted. This cannot be undone.")
        }
    }
    
    // MARK: - Labels UI
    
    private var labelsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !cardLabels.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(cardLabels) { label in
                        LabelChip(label: label) {
                            Task {
                                await appState.removeLabel(boardId: boardId, stackId: card.stackId, cardId: card.id, labelId: label.id)
                            }
                        }
                    }
                }
            }
            Menu {
                ForEach(availableBoardLabels) { label in
                    Button {
                        Task {
                            await appState.assignLabel(boardId: boardId, stackId: card.stackId, cardId: card.id, labelId: label.id)
                        }
                    } label: {
                        Label(label.title, systemImage: "tag.fill")
                    }
                }
                if !availableBoardLabels.isEmpty {
                    Divider()
                }
                Button {
                    newLabelTitle = ""
                    newLabelColor = "31CC7C"
                    showCreateLabel = true
                } label: {
                    Label("Create new tag…", systemImage: "plus.circle")
                }
            } label: {
                Text("Add label")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(board == nil)
        }
    }
    
    private var createLabelSheet: some View {
        CreateLabelSheet(
            title: $newLabelTitle,
            color: $newLabelColor,
            isCreating: $isCreatingLabel,
            onCreate: {
                isCreatingLabel = true
                Task {
                    if let labelId = await appState.createLabel(boardId: boardId, title: newLabelTitle, color: newLabelColor) {
                        await appState.assignLabel(boardId: boardId, stackId: card.stackId, cardId: card.id, labelId: labelId)
                        await MainActor.run {
                            showCreateLabel = false
                            newLabelTitle = ""
                            newLabelColor = "31CC7C"
                        }
                    }
                    await MainActor.run { isCreatingLabel = false }
                }
            },
            onCancel: { showCreateLabel = false }
        )
    }
    
    private func save() {
        isSaving = true
        Task {
            await appState.updateCard(boardId: boardId, stackId: card.stackId, card: card, title: title, description: description)
            await MainActor.run {
                isSaving = false
                dismiss()
                onDismiss()
            }
        }
    }
}

// MARK: - Label chip

private struct LabelChip: View {
    let label: DeckLabel
    var onRemove: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label.title)
                .font(.caption)
                .lineLimit(1)
            if onRemove != nil {
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: label.color ?? "cccccc") ?? .gray.opacity(0.3))
        .foregroundStyle(.white)
        .clipShape(Capsule())
    }
}

// MARK: - Create label sheet

private struct CreateLabelSheet: View {
    @Binding var title: String
    @Binding var color: String
    @Binding var isCreating: Bool
    var onCreate: () -> Void
    var onCancel: () -> Void
    
    private static let presetColors: [(name: String, hex: String)] = [
        ("Green", "31CC7C"),
        ("Blue", "317CCC"),
        ("Red", "FF7A66"),
        ("Yellow", "F1DB50"),
        ("Purple", "9C59B6"),
        ("Orange", "F39C12"),
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            Text("New tag")
                .font(.headline)
            TextField("Tag name", text: $title)
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 6) {
                Text("Color")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(Self.presetColors, id: \.hex) { preset in
                        Button {
                            color = preset.hex
                        } label: {
                            Circle()
                                .fill(Color(hex: preset.hex) ?? .gray)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.3), lineWidth: color == preset.hex ? 3 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    onCreate()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
            }
        }
        .padding(24)
        .frame(width: 280)
    }
}
