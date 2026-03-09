import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var serverInput = ""
    @FocusState private var serverFieldFocused: Bool

    private var serverURL: URL? {
        var s = serverInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.hasPrefix("http") { s = "https://" + s }
        // Require HTTPS for security (App Store and best practice).
        if s.hasPrefix("http://") { s = "https://" + s.dropFirst(7) }
        return URL(string: s)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative)

                Text("Nextcloud Deck")
                    .font(.title.weight(.semibold))

                Text("Sign in with your Nextcloud server to view and manage your boards.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Server URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("https://your-nextcloud.com", text: $serverInput)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)
                        .focused($serverFieldFocused)
                        .onSubmit { signIn() }
                }
                .frame(width: 320)

                if let msg = appState.errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    signIn()
                } label: {
                    Group {
                        if appState.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.9)
                        } else {
                            SwiftUI.Label("Sign in with browser", systemImage: "safari")
                        }
                    }
                    .frame(width: 320, height: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isLoading || serverURL == nil)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(40)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 20, y: 10)

            Spacer()

            Text("Credentials are stored securely in the Keychain.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .padding(.bottom, 24)
        }
        .frame(minWidth: 480, minHeight: 480)
        .onAppear {
            serverFieldFocused = true
        }
    }

    private func signIn() {
        guard let url = serverURL else { return }
        Task { await appState.loginWithBrowser(serverURL: url) }
    }
}

#Preview {
    LoginView()
        .environmentObject(AppState())
}
