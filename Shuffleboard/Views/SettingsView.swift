import SwiftUI

/// Shuffleboard > Settings… (⌘,). For now, which notifications to show (#157); more settings come with #165.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(CardReminderSync.dueRemindersKey) private var remindDue = true
    @AppStorage(CardReminderSync.assignedRemindersKey) private var notifyAssigned = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $remindDue) {
                    Text("Due dates")
                    Text("A day before a card assigned to you is due, and when it's due.")
                }
                Toggle(isOn: $notifyAssigned) {
                    Text("New assignments")
                    Text("When someone assigns a card to you.")
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text(
                    "Shuffleboard checks your boards while it's open. Due date reminders are scheduled ahead, so they "
                        + "arrive even after you quit. Reminders are for the account you're using."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: remindDue) { updateReminders() }
        .onChange(of: notifyAssigned) { updateReminders() }
    }

    private func updateReminders() {
        Task { await appState.updateReminders() }
    }
}
