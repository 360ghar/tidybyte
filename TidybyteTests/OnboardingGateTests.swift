import XCTest
@testable import Tidybyte

/// Pins the first-run onboarding gate.
///
/// The gate matters more than it looks: `hasCompletedOnboarding` is absent for
/// everyone who installed the app before onboarding existed, so the flag alone
/// would re-onboard the entire installed base. The permission state is what
/// distinguishes a fresh install from an existing one.
final class OnboardingGateTests: XCTestCase {

    func testShowsOnFreshInstall() {
        XCTAssertTrue(
            AppPreferences.shouldPresentOnboarding(hasCompleted: false, permissionState: .notDetermined)
        )
    }

    func testHiddenOnceCompleted() {
        XCTAssertFalse(
            AppPreferences.shouldPresentOnboarding(hasCompleted: true, permissionState: .notDetermined)
        )
    }

    /// The upgrade path: no flag on disk, but the user already made a choice.
    func testNeverReonboardsExistingUserWithAccess() {
        XCTAssertFalse(
            AppPreferences.shouldPresentOnboarding(hasCompleted: false, permissionState: .authorized)
        )
    }

    func testNeverReonboardsExistingUserWhoDenied() {
        XCTAssertFalse(
            AppPreferences.shouldPresentOnboarding(hasCompleted: false, permissionState: .denied)
        )
    }

    func testNeverReonboardsExistingLimitedAccessUser() {
        XCTAssertFalse(
            AppPreferences.shouldPresentOnboarding(hasCompleted: false, permissionState: .limited)
        )
    }

    func testNeverReonboardsRestrictedUser() {
        XCTAssertFalse(
            AppPreferences.shouldPresentOnboarding(hasCompleted: false, permissionState: .restricted)
        )
    }

    // MARK: - Completion flag persistence

    func testCompletionFlagRoundTrips() {
        let suiteName = "OnboardingGateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Absent on a fresh install.
        XCTAssertFalse(AppPreferences.hasCompletedOnboarding(in: defaults))

        AppPreferences.saveHasCompletedOnboarding(true, in: defaults)
        XCTAssertTrue(AppPreferences.hasCompletedOnboarding(in: defaults))
    }

    // MARK: - Limited-access notice

    func testLimitedLibraryNoticeRoundTrips() {
        let suiteName = "OnboardingGateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // A limited-access user who has not seen the fuller wording yet.
        // Reads the key directly: the banner owns the only production
        // read/write path via @AppStorage, so there is no helper to test.
        XCTAssertFalse(defaults.bool(forKey: AppPreferences.Key.hasSeenLimitedLibraryNotice))

        defaults.set(true, forKey: AppPreferences.Key.hasSeenLimitedLibraryNotice)
        XCTAssertTrue(defaults.bool(forKey: AppPreferences.Key.hasSeenLimitedLibraryNotice))
    }
}
