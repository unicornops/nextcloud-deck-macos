import SwiftUI

struct NewStackSheet: View {
    let boardId: Int
    var onDismiss: () -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var isSaving = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("New list")
                .font(.headline)
            TextField("List title", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { save() }
            HStack {
                Button("Cancel") {
                    dismiss()
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
    
    private func save() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        isSaving = true
        Task {
            await appState.createStack(boardId: boardId, title: t)
            isSaving = false
            dismiss()
            onDismiss()
        }
    }
}
