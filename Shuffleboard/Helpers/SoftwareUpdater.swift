import Combine
import Sparkle
import SwiftUI

// MARK: - SoftwareUpdater

/// In-app updates via [Sparkle](https://sparkle-project.org).
///
/// The feed (`SUFeedURL`) is the `appcast.xml` attached to the latest GitHub release, and every update is
/// verified against `SUPublicEDKey` (both in Info.plist). The release workflow signs the update with the
/// matching private key and generates the appcast.
@MainActor
final class SoftwareUpdater: ObservableObject {
    /// False while a check is already running, so "Check for Updates…" can be disabled.
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController

    init() {
        // The app also hosts the unit tests; don't check for updates or show update UI there.
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.controller = SPUStandardUpdaterController(
            startingUpdater: !isRunningTests,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

// MARK: - Menu item

/// The "Check for Updates…" menu item.
struct CheckForUpdatesButton: View {
    @ObservedObject var updater: SoftwareUpdater

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
