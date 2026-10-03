import SwiftUI

struct NewBoardSheet: View {
    var onDismiss: () -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var color = BoardColorPickerView.defaultColor
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New board")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Board title")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Enter board name", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { save() }
            }

            BoardColorPickerView(selectedHex: $color)

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
            let success = await appState.createBoard(title: t, color: color)
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
