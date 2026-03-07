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
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isSaving || title.isEmpty)
            }
            .padding()
            Divider()
            
            Form {
                TextField("Title", text: $title)
                TextEditor(text: $description)
                    .frame(minHeight: 120)
                    .font(.body)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 440, height: 360)
    }
    
    private func save() {
        isSaving = true
        Task {
            await appState.updateCard(boardId: boardId, stackId: card.stackId, card: card, title: title, description: description)
            isSaving = false
            dismiss()
            onDismiss()
        }
    }
}
