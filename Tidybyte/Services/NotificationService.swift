import UserNotifications

enum NotificationService {

    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            AppLog.notifications.error("Notification authorization request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func scheduleWeeklyReminder(
        weekday: Int,
        hour: Int = 10,
        minute: Int = 0,
        screenshotCount: Int? = nil,
        largeFileCount: Int? = nil,
        librarySize: String? = nil
    ) async {
        let center = UNUserNotificationCenter.current()

        // Remove existing reminders
        center.removePendingNotificationRequests(withIdentifiers: ["weekly-cleanup-reminder"])

        var dateComponents = DateComponents()
        dateComponents.weekday = weekday
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = "Time for a Photo Cleanup"
        content.sound = .default

        // Dynamic body with real counts
        if let screenshots = screenshotCount, let largeFiles = largeFileCount, let size = librarySize {
            var parts: [String] = []
            if screenshots > 0 { parts.append("\(screenshots) screenshots") }
            if largeFiles > 0 { parts.append("\(largeFiles) large files") }

            if parts.isEmpty {
                content.body = "Your library is using \(size). Review your photos and free up space."
            } else {
                content.body = "You have \(parts.joined(separator: " and ")) to review. Your library is using \(size)."
            }
        } else {
            content.body = "Review your photos and free up storage space."
        }

        let request = UNNotificationRequest(
            identifier: "weekly-cleanup-reminder",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            AppLog.notifications.error("Failed to schedule weekly reminder: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func cancelAllReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["weekly-cleanup-reminder"]
        )
    }

    static func isPermissionGranted() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
    }
}
