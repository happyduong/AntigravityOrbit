import Foundation
import UserNotifications
import AppKit

public class NotificationManager {
    public static let shared = NotificationManager()

    private init() {
        requestAuthorization()
    }

    public func requestAuthorization() {
        if #available(macOS 10.14, *) {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error = error {
                    print("[NotificationManager] Auth error: \(error)")
                }
            }
        }
    }

    public func sendRotationNotification(oldAccount: String, newAccount: String, newQuota: Int, reason: String) {
        guard ConfigManager.shared.config.notificationsEnabled else { return }

        let title = L10n.tr("notif.auto_rotate_title")
        let subtitle = L10n.tr("notif.auto_rotate_subtitle")
        let body = L10n.tr("notif.auto_rotate_body", oldAccount, reason, newAccount, newQuota)

        if #available(macOS 10.14, *) {
            let content = UNMutableNotificationContent()
            content.title = title
            content.subtitle = subtitle
            content.body = body
            if ConfigManager.shared.config.soundEnabled {
                content.sound = UNNotificationSound.default
            }

            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if error != nil {
                    // Fallback to osascript
                    self.sendAppleScriptNotification(title: title, subtitle: subtitle, body: body)
                }
            }
        } else {
            sendAppleScriptNotification(title: title, subtitle: subtitle, body: body)
        }
    }

    public func sendManualSwitchNotification(account: String, quota: Int) {
        guard ConfigManager.shared.config.notificationsEnabled else { return }

        let title = L10n.tr("notif.auto_rotate_title")
        let subtitle = L10n.tr("notif.manual_switch_subtitle")
        let body = L10n.tr("notif.manual_switch_body", account, quota)

        sendAppleScriptNotification(title: title, subtitle: subtitle, body: body)
    }

    private func sendAppleScriptNotification(title: String, subtitle: String, body: String) {
        let soundClause = ConfigManager.shared.config.soundEnabled ? "sound name \"Glass\"" : ""
        let script = "display notification \"\(body.replacingOccurrences(of: "\"", with: "\\\""))\" with title \"\(title.replacingOccurrences(of: "\"", with: "\\\""))\" subtitle \"\(subtitle.replacingOccurrences(of: "\"", with: "\\\""))\" \(soundClause)"

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
        }
    }
}
