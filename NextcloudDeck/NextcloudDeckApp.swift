import SwiftUI

@main
struct NextcloudDeckApp: App {
    @StateObject private var appState = AppState()
    
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
                Button("About Nextcloud Deck") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [:])
                }
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
