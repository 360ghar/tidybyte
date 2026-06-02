import XCTest
@testable import Tidybyte

final class AppPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultValuesFallbackCleanly() {
        XCTAssertEqual(AppPreferences.defaultSwipeFilter(in: defaults), .notSwipedYet)
        XCTAssertEqual(AppPreferences.similarPhotoTimeWindow(in: defaults), 5.0)
        XCTAssertEqual(AppPreferences.blurSensitivity(in: defaults), .medium)
        XCTAssertEqual(AppPreferences.largeFileThresholdMB(in: defaults), 10.0)
        XCTAssertEqual(AppPreferences.defaultCompressionPresetID(in: defaults), "1080p")
        XCTAssertFalse(AppPreferences.remindersEnabled(in: defaults))
        XCTAssertEqual(AppPreferences.reminderWeekday(in: defaults), 0)
        XCTAssertEqual(AppPreferences.recentAlbumIds(in: defaults), [])
    }

    func testTypedPreferenceRoundTrip() {
        AppPreferences.saveDefaultSwipeFilter(.allMedia, in: defaults)
        AppPreferences.saveSimilarPhotoTimeWindow(12, in: defaults)
        AppPreferences.saveBlurSensitivity(.high, in: defaults)
        AppPreferences.saveLargeFileThresholdMB(42, in: defaults)
        AppPreferences.saveDefaultCompressionPresetID("720p", in: defaults)
        AppPreferences.saveRemindersEnabled(true, in: defaults)
        AppPreferences.saveReminderWeekday(4, in: defaults)
        AppPreferences.saveRecentAlbumIds(["one", "two"], in: defaults)

        XCTAssertEqual(AppPreferences.defaultSwipeFilter(in: defaults), .allMedia)
        XCTAssertEqual(AppPreferences.similarPhotoTimeWindow(in: defaults), 12)
        XCTAssertEqual(AppPreferences.blurSensitivity(in: defaults), .high)
        XCTAssertEqual(AppPreferences.largeFileThresholdMB(in: defaults), 42)
        XCTAssertEqual(AppPreferences.defaultCompressionPresetID(in: defaults), "720p")
        XCTAssertTrue(AppPreferences.remindersEnabled(in: defaults))
        XCTAssertEqual(AppPreferences.reminderWeekday(in: defaults), 4)
        XCTAssertEqual(AppPreferences.recentAlbumIds(in: defaults), ["one", "two"])
    }
}
