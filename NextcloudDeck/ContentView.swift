import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.showingLogin {
                LoginView()
            } else {
                mainInterface
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.showingLogin)
        .sheet(isPresented: $appState.showingAbout) {
            AboutSheet()
        }
    }

    private var mainInterface: some View {
        NavigationSplitView {
            BoardListView()
        } detail: {
            BoardDetailView()
        }
        .task {
            await appState.loadBoardsIfNeeded()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("About Nextcloud Deck", systemImage: "info.circle") {
                        appState.showingAbout = true
                    }
                    Divider()
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await appState.refresh() }
                    }
                    Divider()
                    Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
                        appState.logout()
                    }
                } label: {
                    Image(systemName: "person.circle")
                }
                .help("Account and actions")
                .accessibilityLabel("Account menu")
            }
        }
    }
}

private struct BuildMetadata {
    static let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Nextcloud Deck"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    static let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    static let gitCommit = Bundle.main.object(forInfoDictionaryKey: "BuildGitCommit") as? String ?? "unknown"
    static let buildRef = Bundle.main.object(forInfoDictionaryKey: "BuildRef") as? String ?? "local"
    static let buildDateUTC = Bundle.main.object(forInfoDictionaryKey: "BuildDateUTC") as? String ?? "unknown"

    static var shortCommit: String {
        gitCommit == "unknown" ? gitCommit : String(gitCommit.prefix(7))
    }

    static var summary: String {
        """
        Version: \(version)
        Build: \(buildNumber)
        Ref: \(buildRef)
        Commit: \(gitCommit)
        Built: \(buildDateUTC)
        """
    }
}

private struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: 4) {
                Text(BuildMetadata.appName)
                    .font(.title2.weight(.semibold))
                Text("Version \(BuildMetadata.version) (\(BuildMetadata.buildNumber))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    metadataLabel("Ref")
                    metadataValue(BuildMetadata.buildRef)
                }
                GridRow {
                    metadataLabel("Commit")
                    metadataValue(BuildMetadata.shortCommit)
                }
                GridRow {
                    metadataLabel("Built")
                    metadataValue(BuildMetadata.buildDateUTC)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                Button("Copy Build Info") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(BuildMetadata.summary, forType: .string)
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func metadataLabel(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
    }

    private func metadataValue(_ value: String) -> some View {
        Text(value)
            .textSelection(.enabled)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
