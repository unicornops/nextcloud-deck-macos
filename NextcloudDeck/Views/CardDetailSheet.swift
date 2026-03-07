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
                Section {
                    Button("Delete card", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 440, height: 360)
        .navigationTitle("Edit Card")
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
