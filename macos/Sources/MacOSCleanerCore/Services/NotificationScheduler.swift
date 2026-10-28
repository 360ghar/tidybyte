import Foundation
import os
import UserNotifications

public actor NotificationScheduler {
    private static let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "NotificationScheduler")

    public init() {}

    public func requestAuthorization() async -> Bool {
        guard canUseUserNotifications else {
            return false
        }
        // Never prompt from an unbundled process (tests, command-line runs):
        // UNUserNotificationCenter.requestAuthorization can hang indefinitely
        // without a real app bundle. Scheduling still proceeds there; only the
        // interactive prompt is skipped.
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return false
        }
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Self.logger.warning("Notification authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    public func scheduleScanCompletedNotification(reclaimedBytes: Int64) async {
        guard canUseUserNotifications else {
            return
        }
        // Request authorization lazily in context (first scan completing) instead
        // of at app launch. No-op when the user already decided — the system
        // returns the current status without re-prompting.
        _ = await requestAuthorization()
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Scan Complete")
        content.body = String(localized: "Review cleanup suggestions for \(reclaimedBytes.formattedByteCount).")
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "scan-complete-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Self.logger.warning("Failed to schedule scan notification: \(error.localizedDescription)")
        }
    }

    public func scheduleWeeklyGrowthDigest() async {
        guard canUseUserNotifications else {
            return
        }
        // See scheduleScanCompletedNotification: request in context, no re-prompt
        // once the user has decided.
        _ = await requestAuthorization()
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Weekly Storage Digest", comment: "Weekly digest notification title")
        content.body = String(localized: "Your weekly storage report is ready. Open Tidybyte to review what grew this week.", comment: "Weekly digest notification body")
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.weekday = 2
        dateComponents.hour = 9
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: Self.weeklyDigestIdentifier, content: content, trigger: trigger)

        // Remove any previously scheduled digest with the same identifier so
        // repeated calls (e.g. after every scan) don't fail with a duplicate-error.
        // Without this, UNUserNotificationCenter.add throws error 1404 on the
        // second invocation, leaving the original schedule in place but logging
        // a misleading warning.
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.weeklyDigestIdentifier])

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Self.logger.warning("Failed to schedule weekly growth digest: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Offered after an app disappears from /Applications. Tapping it opens
    /// Leftovers with that app's remaining data staged for review.
    public func scheduleLeftoversNotification(appName: String, bundleID: String, bundlePath: String) async {
        guard canUseUserNotifications else { return }
        _ = await requestAuthorization()
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(appName) was removed", comment: "Leftovers notification title")
        content.body = String(
            localized: "Its settings and caches are still on this Mac. Review them in Tidybyte.",
            comment: "Leftovers notification body")
        // Everything needed to rebuild the app survives a relaunch of Tidybyte.
        content.userInfo = [
            Self.routeKey: "leftovers", Self.bundleIDKey: bundleID, Self.appNameKey: appName, Self.bundlePathKey: bundlePath
        ]
        let request = UNNotificationRequest(identifier: "leftovers-\(bundleID)", content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Self.logger.warning("Failed to schedule leftovers notification: \(error.localizedDescription, privacy: .public)")
        }
    }

    public static let routeKey = "route"
    public static let bundleIDKey = "bundleID"
    public static let appNameKey = "appName"
    public static let bundlePathKey = "bundlePath"
    private static let weeklyDigestIdentifier = "weekly-growth-digest"

    private var canUseUserNotifications: Bool {
        #if DEBUG
        return Bundle.main.bundleURL.pathExtension == "app" || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #else
        return Bundle.main.bundleURL.pathExtension == "app"
        #endif
    }
}
