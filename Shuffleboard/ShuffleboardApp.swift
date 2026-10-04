import SwiftUI

@main
struct ShuffleboardApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var updater = SoftwareUpdater()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh") {
                    Task { await appState.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Shuffleboard") {
                    appState.showingAbout = true
                }
                CheckForUpdatesButton(updater: updater)
            }
            CommandGroup(replacing: .help) {
                Button("Deck API Reference") {
                    if let url = URL(string: "https://deck.readthedocs.io/en/latest/API/") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}
