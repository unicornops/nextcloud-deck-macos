import SwiftUI

struct NewStackSheet: View {
    let boardId: Int
    var onDismiss: () -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New list")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("List title")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Enter list name", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { save() }
            }

            CreateSheetFooter(
                isDisabled: title.trimmingCharacters(in: .whitespaces).isEmpty,
                isSaving: $isSaving
            ) {
                save()
            } onCancel: {
                dismiss()
                onDismiss()
            }
        }
        .padding(24)
        .frame(width: 320)
        .onAppear {
            appState.errorMessage = nil
        }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        isSaving = true
        appState.errorMessage = nil
        Task {
            let success = await appState.createStack(boardId: boardId, title: t)
            await MainActor.run {
                isSaving = false
                if success {
                    dismiss()
                    onDismiss()
                }
            }
        }
    }
}
