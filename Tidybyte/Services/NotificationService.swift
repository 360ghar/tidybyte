import UserNotifications

enum NotificationService {
    /// Reminders fire at 10:00 on the chosen weekday.
    static let reminderHour = 10

    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            AppLog.notifications.error("Notification authorization request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Returns true when the request was accepted by the notification center.
    static func scheduleWeeklyReminder(weekday: Int, hour: Int = reminderHour, minute: Int = 0) async -> Bool {
        let center = UNUserNotificationCenter.current()

        // Remove existing reminders
        center.removePendingNotificationRequests(withIdentifiers: ["weekly-cleanup-reminder"])

        var dateComponents = DateComponents()
        dateComponents.weekday = weekday
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        // No counts in the text: a repeating reminder keeps the text it was
        // scheduled with, so counts went stale for the users who open the app
        // least, the people the reminder is for.
        let content = UNMutableNotificationContent()
        content.title = "Time for a Photo Cleanup"
        content.body = "Screenshots and large files add up. Take a few minutes to review them."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "weekly-cleanup-reminder",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            return true
        } catch {
            AppLog.notifications.error("Failed to schedule weekly reminder: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func cancelAllReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["weekly-cleanup-reminder"]
        )
    }

    static func isPermissionGranted() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        // Provisional and ephemeral users DO receive the scheduled reminder —
        // treating them as un-granted silently stopped the daily copy refresh
        // for those users (A3).
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }
}

/// Routes a reminder tap to the Cleanup tab and shows a reminder that arrives
/// while the app is open. Set as the center's delegate at launch.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationRouter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            PendingRoute.shared.link = .cleanupHome
        }
    }
}
