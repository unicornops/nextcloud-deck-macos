import SwiftUI

// MARK: - ErrorBanner

/// Dismissible banner for `AppState.actionError`: failures from actions that have no UI of
/// their own (moving or deleting cards, label changes, attachments…).
///
/// A banner rather than an alert, because the main window cannot present an alert while a
/// sheet such as `CardDetailSheet` is open; the sheet shows the same banner itself.
struct ErrorBanner: View {
    let message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .lineLimit(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.red.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - View modifier

extension View {
    /// Overlays the `AppState.actionError` banner along the bottom edge of the view.
    func actionErrorBanner(_ appState: AppState) -> some View {
        overlay(alignment: .bottom) {
            if let message = appState.actionError {
                ErrorBanner(message: message) {
                    appState.actionError = nil
                }
                .frame(maxWidth: 520)
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.actionError)
    }
}

#Preview {
    ErrorBanner(message: "Permission denied") {}
        .padding()
        .frame(width: 480)
}
