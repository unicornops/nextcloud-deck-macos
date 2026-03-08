import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var serverInput = ""
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?
    
    enum Field { case server, username, password }
    
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

                // Sign in with browser (supports 2FA)
                Button {
                    signInWithBrowser()
                } label: {
                    Group {
                        if appState.isLoading && !serverInput.isEmpty && username.isEmpty {
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

                Text("Use this if you have two-factor authentication (2FA) enabled.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Divider()
                    .frame(width: 280)
                    .padding(.vertical, 4)

                Text("Or sign in with password")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Server URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("https://your-nextcloud.com", text: $serverInput)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)
                        .focused($focusedField, equals: .server)
                        .onSubmit { focusedField = .username }

                    Text("Username")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.username)
                        .focused($focusedField, equals: .username)
                        .onSubmit { focusedField = .password }

                    Text("Password")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("Password or app password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .onSubmit { signInWithPassword() }
                }
                .frame(width: 320)

                if let msg = appState.errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button("Sign in with password") {
                    signInWithPassword()
                }
                .buttonStyle(.bordered)
                .disabled(appState.isLoading || serverURL == nil || username.isEmpty || password.isEmpty)
            }
            .padding(40)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
            
            Spacer()
            
            Text("Credentials are stored securely in the Keychain. Browser sign-in works with 2FA.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .padding(.bottom, 24)
        }
        .frame(minWidth: 480, minHeight: 580)
        .onAppear {
            focusedField = .server
        }
    }

    private func signInWithBrowser() {
        guard let url = serverURL else { return }
        Task { await appState.loginWithBrowser(serverURL: url) }
    }

    private func signInWithPassword() {
        guard let url = serverURL else { return }
        Task { await appState.login(serverURL: url, username: username, password: password) }
    }
}

#Preview {
    LoginView()
        .environmentObject(AppState())
}
