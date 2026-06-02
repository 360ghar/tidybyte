import XCTest
@testable import Tidybyte

@MainActor
final class AppNavigationTests: XCTestCase {
    func testShowCleanupRoutesToSpecificTool() {
        let navigation = AppNavigation()
        let initialDismissID = navigation.swipeDismissRequestID

        navigation.showCleanup(tool: .screenshots)

        XCTAssertEqual(navigation.selectedTab, .cleanup)
        XCTAssertEqual(navigation.cleanupPath, [.screenshots])
        XCTAssertNotEqual(navigation.swipeDismissRequestID, initialDismissID)
    }

    func testShowCleanupWithoutToolClearsPath() {
        let navigation = AppNavigation()
        navigation.cleanupPath = [.duplicates]

        navigation.showCleanup()

        XCTAssertEqual(navigation.selectedTab, .cleanup)
        XCTAssertTrue(navigation.cleanupPath.isEmpty)
    }

    func testReturnToSwipeHomeClearsCleanupPathAndRequestsDismissal() {
        let navigation = AppNavigation()
        navigation.selectedTab = .cleanup
        navigation.cleanupPath = [.videoCompression]
        let initialDismissID = navigation.swipeDismissRequestID

        navigation.returnToSwipeHome()

        XCTAssertEqual(navigation.selectedTab, .swipe)
        XCTAssertTrue(navigation.cleanupPath.isEmpty)
        XCTAssertNotEqual(navigation.swipeDismissRequestID, initialDismissID)
    }

    func testShowCleanupHomeClearsPathAndStaysOnCleanupTab() {
        let navigation = AppNavigation()
        navigation.selectedTab = .storage
        navigation.cleanupPath = [.duplicates]
        let initialDismissID = navigation.swipeDismissRequestID

        navigation.showCleanupHome()

        XCTAssertEqual(navigation.selectedTab, .cleanup)
        XCTAssertTrue(navigation.cleanupPath.isEmpty)
        XCTAssertNotEqual(navigation.swipeDismissRequestID, initialDismissID)
    }
}
