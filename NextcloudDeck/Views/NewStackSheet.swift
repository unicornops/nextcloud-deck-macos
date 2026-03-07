import SwiftUI

struct NewStackSheet: View {
    let boardId: Int
    var onDismiss: () -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var isSaving = false
    
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("List title") {
                    TextField("List title", text: $title)
                        .onSubmit { save() }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity)
            
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
                            .frame(minWidth: 60)
                    } else {
                        Text("Create")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
            .padding()
        }
        .frame(width: 320)
        .navigationTitle("New list")
    }
    
    private func save() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        isSaving = true
        Task {
            await appState.createStack(boardId: boardId, title: t)
            await MainActor.run {
                isSaving = false
                dismiss()
                onDismiss()
            }
        }
    }
}
