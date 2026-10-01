import AppKit
import UserNotifications

/// Posts macOS notifications for new items and handles clicks on them.
@MainActor
final class SystemNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SystemNotifier()

    /// Called when the user clicks a notification. The thread ID is set for GitHub notifications.
    var onOpen: ((URL, _ threadID: String?) -> Void)?

    private var center: UNUserNotificationCenter { .current() }

    func activate() {
        center.delegate = self
    }

    /// Asks for permission the first time; afterwards returns the stored decision.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Posts up to three items individually, then one summary for the rest.
    func post(_ items: [FeedItem], from tab: TabConfig) {
        let shown = items.prefix(3)
        for item in shown {
            let content = UNMutableNotificationContent()
            content.title = tab.title
            content.subtitle = item.number.map { "\(item.repository) #\($0)" } ?? item.repository
            content.body = item.title
            content.sound = .default
            content.threadIdentifier = tab.id.uuidString
            content.userInfo = ["url": item.url.absoluteString, "threadID": item.notificationThreadID ?? ""]
            center.add(UNNotificationRequest(identifier: "\(tab.id)-\(item.id)", content: content, trigger: nil))
        }

        let remaining = items.count - shown.count
        guard remaining > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = tab.title
        content.body = "\(remaining) more new \(remaining == 1 ? "item" : "items")"
        content.threadIdentifier = tab.id.uuidString
        content.userInfo = ["url": tab.webURL.absoluteString]
        center.add(UNNotificationRequest(identifier: "\(tab.id)-summary-\(Date().timeIntervalSince1970)", content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let url = (info["url"] as? String).flatMap(URL.init(string:))
        let threadID = (info["threadID"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        Task { @MainActor in
            if let url { self.onOpen?(url, threadID) }
            completionHandler()
        }
    }

    /// Menu bar apps are never "frontmost" in the usual sense; always show the banner.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
