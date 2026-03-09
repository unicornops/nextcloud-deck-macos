import SwiftUI

struct NewBoardSheet: View {
    var onDismiss: () -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var color = "0082c9"
    @State private var isSaving = false

    private static let presetColors: [(name: String, hex: String)] = [
        ("Blue", "0082c9"),
        ("Green", "31CC7C"),
        ("Red", "FF7A66"),
        ("Yellow", "F1DB50"),
        ("Purple", "9C59B6"),
        ("Orange", "F39C12"),
    ]

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
                        .accessibilityLabel(preset.name)
                    }
                }
            }

            if let err = appState.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(4)
            }

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
