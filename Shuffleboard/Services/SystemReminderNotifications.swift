import AppKit
import UserNotifications

/// Card reminders as macOS notifications (UserNotifications). Also receives clicks on them: `CardReminderClicks`
/// passes the card on to whoever opens it.
@MainActor
final class SystemReminderNotifications: ReminderNotifications {
    private static let idPrefix = "card-reminder|"

    func requestPermission() async -> Bool {
        await Self.requestAuthorization()
    }

    func pendingIds() async -> Set<String> {
        await Set(Self.pendingIdentifiers().filter { $0.hasPrefix(Self.idPrefix) })
    }

    func add(_ reminder: CardReminder, at date: Date?) async {
        await Self.add(reminder, at: date)
    }

    func remove(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Array(ids))
    }

    // The notification centre's objects stay inside these, off the main actor.

    private nonisolated static func requestAuthorization() async -> Bool {
        await (try? UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    private nonisolated static func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    private nonisolated static func add(_ reminder: CardReminder, at date: Date?) async {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.userInfo = CardReminderClicks.userInfo(for: reminder)
        let trigger = date.map {
            UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: $0),
                repeats: false
            )
        }
        let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// The card a clicked reminder is about.
struct ClickedReminder: Equatable, Sendable {
    let accountId: String
    let boardId: Int
    let cardId: Int
}

/// Receives clicks on card reminders, and shows reminders while the app is in front too. Set as the notification
/// centre's delegate as the app starts, so a click that launches the app isn't missed; the click waits in `clicked`
/// until the app opens the card.
@MainActor
final class CardReminderClicks: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = CardReminderClicks()

    @Published var clicked: ClickedReminder?

    func start() {
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated static func userInfo(for reminder: CardReminder) -> [String: Any] {
        ["accountId": reminder.accountId, "boardId": reminder.boardId, "cardId": reminder.cardId]
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let accountId = info["accountId"] as? String,
              let boardId = info["boardId"] as? Int,
              let cardId = info["cardId"] as? Int else { return }
        let clicked = ClickedReminder(accountId: accountId, boardId: boardId, cardId: cardId)
        await MainActor.run {
            NSApp.activate()
            self.clicked = clicked
        }
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
