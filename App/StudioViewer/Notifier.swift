import Foundation
import UserNotifications

/// System notifications when something goes wrong: Capture One stops answering (after a grace
/// period, so a quick hiccup stays quiet), the viewer stops unexpectedly (with a Restart button),
/// or someone keeps guessing the remote viewing code.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    weak var engine: Engine?
    private var lostTimer: Task<Void, Never>?
    private var toldLost = false
    private static let grace: Duration = .seconds(10)
    private static let crashCategory = "crash"
    nonisolated private static let restartAction = "restart"

    func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let restart = UNNotificationAction(identifier: Self.restartAction, title: "Restart")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.crashCategory, actions: [restart], intentIdentifiers: []),
        ])
        if UserDefaults.standard.bool(forKey: Prefs.notify) {
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func handle(_ alert: Engine.Alert) {
        switch alert {
        case .captureOneLost:
            lostTimer?.cancel()
            lostTimer = Task {
                try? await Task.sleep(for: Self.grace)
                guard !Task.isCancelled, engine?.phase == .captureOneLost else { return }
                toldLost = true
                post("Capture One isn't answering",
                     "Viewers are paused. Check that Capture One is open and Live for Studio is sharing.")
            }
        case .captureOneBack:
            lostTimer?.cancel()
            if toldLost {
                toldLost = false
                post("Capture One is back", "Viewers are live again.")
            }
        case .crashed(let reason):
            lostTimer?.cancel()
            toldLost = false
            post("StudioViewer stopped", reason, category: Self.crashCategory)
        case .error(let message):
            post("StudioViewer", message)
        case .guessing:
            post("Someone is guessing the viewing code",
                 "Remote unlocking is paused for a few minutes. Consider changing the code.")
        case .tunnelDropped:
            post("Remote sharing dropped", "People outside the studio can't see the shoot. StudioViewer keeps trying to reconnect.")
        case .tunnelBack:
            post("Remote sharing is back", "People outside the studio can watch again.")
        case .tunnelFailed(let reason):
            post("Remote sharing stopped", reason)
        }
    }

    private func post(_ title: String, _ body: String, category: String? = nil) {
        guard UserDefaults.standard.bool(forKey: Prefs.notify) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category { content.categoryIdentifier = category }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // Show notifications even while StudioViewer is the active app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == Self.restartAction else { return }
        await MainActor.run { engine?.start() }
    }
}
