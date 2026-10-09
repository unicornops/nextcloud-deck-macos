import SwiftUI

@main
struct ShuffleboardApp: App {
    @StateObject private var appState = AppState.atLaunch()
    @StateObject private var updater = SoftwareUpdater()

    init() {
        // Before the app finishes launching, so a click on a notification that launches it isn't missed.
        CardReminderClicks.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                #if DEBUG
                .onAppear { UITestLaunch.applyAppearance() }
                #endif
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 700)
        .commands {
            BoardCommands(appState: appState)
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
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
