import UserNotifications
import Photos

@MainActor
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

    struct Snapshot: Sendable {
        let stats: MediaLibraryStats
        let date: Date
        let isLimited: Bool
    }

    private static var latestSnapshot: Snapshot?
    private static var revision = 0
    private static var schedulingTask: Task<Bool, Never>?

    static func updateSnapshot(_ snapshot: Snapshot?) {
        let snapshot = authorizedSnapshot(snapshot, permission: PHPhotoLibrary.authorizationStatus(for: .readWrite))
        if let snapshot, let latestSnapshot, snapshot.date < latestSnapshot.date { return }
        latestSnapshot = snapshot
    }

    nonisolated static func authorizedSnapshot(_ snapshot: Snapshot?, permission: PHAuthorizationStatus) -> Snapshot? {
        guard permission == .authorized || permission == .limited,
              let snapshot, snapshot.isLimited == (permission == .limited) else { return nil }
        return snapshot
    }

    nonisolated static func reminderBody(snapshot: Snapshot?) -> String {
        guard let snapshot else {
            return L10n.string("Screenshots and large files add up. Take a few minutes to review them.")
        }
        let stats = snapshot.stats
        var parts: [String] = []
        if stats.screenshotCount > 0 {
            // `L10n.format` routes through the catalog's plural variations, so
            // languages with more than two plural forms (Arabic has six,
            // Russian four) get their own rules instead of an appended "s".
            var text = L10n.format("%lld screenshot", fallback: "%lld screenshots", stats.screenshotCount)
            if stats.screenshotUnknownSizeCount == 0, stats.screenshotBytes > 0 {
                text += " (\(stats.screenshotBytes.formattedFileSize))"
            }
            parts.append(text)
        }
        if stats.largeFileCount > 0 {
            var text = L10n.format("%lld large file", fallback: "%lld large files", stats.largeFileCount)
            if stats.largeFileBytes > 0 {
                text += " (\(stats.largeFileBytes.formattedFileSize))"
            }
            parts.append(text)
        }
        guard !parts.isEmpty else { return reminderBody(snapshot: nil) }
        let date = Formatters.mediumDate(snapshot.date)
        let scope = snapshot.isLimited ? L10n.string(" in selected photos") : ""
        // `Formatters.list` supplies the locale's conjunction ("and", "und",
        // "y", "و") rather than a hardcoded comma.
        return L10n.format(
            "Last scan, %@: %@ to review%@.",
            fallback: "Last scan, %@: %@ to review%@.",
            date, Formatters.list(parts), scope
        )
    }

    /// Serialize replacements so an older add cannot overwrite a newer setting.
    static func scheduleWeeklyReminder(weekday: Int, hour: Int = reminderHour, minute: Int = 0) async -> Bool {
        revision += 1
        let token = revision
        let previous = schedulingTask
        let snapshot = latestSnapshot
        let task = Task { @MainActor in
            _ = await previous?.value
            let center = UNUserNotificationCenter.current()
            guard token == revision, AppPreferences.remindersEnabled(),
                  AppPreferences.reminderWeekday() == weekday, (1...7).contains(weekday),
                  await isPermissionGranted(), token == revision,
                  AppPreferences.remindersEnabled() else {
                if token == revision {
                    center.removePendingNotificationRequests(withIdentifiers: ["weekly-cleanup-reminder"])
                }
                return false
            }
            let photoPermission = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            var components = DateComponents()
            components.weekday = weekday
            components.hour = hour
            components.minute = minute
            let content = UNMutableNotificationContent()
            content.title = L10n.string("Time for a Photo Cleanup")
            content.body = reminderBody(snapshot: authorizedSnapshot(snapshot, permission: photoPermission))
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "weekly-cleanup-reminder", content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            )
            do {
                try await center.add(request)
                guard token == revision, AppPreferences.remindersEnabled(),
                      AppPreferences.reminderWeekday() == weekday,
                      photoPermission == PHPhotoLibrary.authorizationStatus(for: .readWrite) else {
                    center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                    return false
                }
                return true
            } catch {
                AppLog.notifications.error("Failed to schedule weekly reminder: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        schedulingTask = task
        let result = await task.value
        if token == revision { schedulingTask = nil }
        return result
    }

    static func cancelAllReminders() {
        revision += 1
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["weekly-cleanup-reminder"])
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
