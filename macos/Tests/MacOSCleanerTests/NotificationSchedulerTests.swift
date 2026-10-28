import Foundation
@testable import MacOSCleanerCore
import XCTest

final class NotificationSchedulerTests: XCTestCase {
    func testNotificationSchedulerCanBeCreated() {
        let scheduler = NotificationScheduler()
        XCTAssertNotNil(scheduler)
    }

    func testNotificationSchedulerRequestAuthorization() async {
        let scheduler = NotificationScheduler()
        // Test processes run unbundled, so authorization can never be granted:
        // the scheduler guards on app-bundle detection and otherwise surfaces
        // the denial (UNUserNotificationCenter errors are caught and map to false).
        let authorized = await scheduler.requestAuthorization()
        XCTAssertFalse(authorized, "Authorization cannot be granted without a real app bundle")
    }

    func testNotificationSchedulerScheduleScanCompleted() async {
        let scheduler = NotificationScheduler()
        // Scheduling must complete without throwing or crashing when unbundled.
        // When notifications are unavailable the scheduler returns early; when
        // UNUserNotificationCenter is reachable, add() errors are caught and
        // logged. Either way, no crash and the scheduler stays usable.
        await scheduler.scheduleScanCompletedNotification(reclaimedBytes: 1_000_000)
        await scheduler.scheduleScanCompletedNotification(reclaimedBytes: 2_000_000)
        let authorized = await scheduler.requestAuthorization()
        XCTAssertFalse(authorized, "Scheduling must not change the unbundled authorization outcome")
    }

    func testNotificationSchedulerScheduleWeeklyDigest() async {
        let scheduler = NotificationScheduler()
        // Scheduling twice exercises the removePendingNotificationRequests +
        // add path; both calls must complete without crashing when unbundled.
        await scheduler.scheduleWeeklyGrowthDigest()
        await scheduler.scheduleWeeklyGrowthDigest()
        let authorized = await scheduler.requestAuthorization()
        XCTAssertFalse(authorized, "Scheduling must not change the unbundled authorization outcome")
    }
}
