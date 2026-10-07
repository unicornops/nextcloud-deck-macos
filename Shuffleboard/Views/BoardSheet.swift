import SwiftUI

/// Creates a board, or with `board` set, renames and recolours that board.
struct BoardSheet: View {
    /// The board to edit; nil creates a new one.
    var board: Board?
    var onDismiss: () -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var color: String
    @State private var isSaving = false

    init(board: Board? = nil, onDismiss: @escaping () -> Void) {
        self.board = board
        self.onDismiss = onDismiss
        _title = State(initialValue: board?.title ?? "")
        let color = board?.color ?? ""
        _color = State(initialValue: color.isEmpty ? BoardColorPickerView.defaultColor : color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(board == nil ? "New board" : "Edit board")
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
                isSaving: $isSaving,
                actionTitle: board == nil ? "Create" : "Save"
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
        guard !t.isEmpty, !isSaving else { return }
        isSaving = true
        appState.errorMessage = nil
        Task {
            let success = if let board {
                await appState.updateBoard(id: board.id, title: t, color: color)
            } else {
                await appState.createBoard(title: t, color: color)
            }
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
