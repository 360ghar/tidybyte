import XCTest

/// Layout integrity for the first-run flow at large text sizes.
///
/// The Dynamic Type work is a *layout* claim, and static analysis cannot verify
/// it: reading the source shows that a control is scaled, not whether the scaled
/// control still fits on screen. These tests run the real app and assert the
/// controls remain reachable.
///
/// The first-run flow is the target because it is the one screen guaranteed to
/// render regardless of the simulator's persisted photo-permission grant — the
/// `-uitest-reset-onboarding` launch argument forces it (see `RootView`).
///
/// `-UIPreferredContentSizeCategoryName` is the documented way to set the
/// content size category at launch.
final class DynamicTypeUITests: XCTestCase {

    /// The largest accessibility size. Anything that survives this survives
    /// every smaller size, because each control's growth is monotonic.
    private static let accessibilityXXXL = "UICTContentSizeCategoryAccessibilityXXXL"

    private let timeout: TimeInterval = 20

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchAtOnboarding(contentSize: String?) -> XCUIApplication {
        let app = XCUIApplication()
        // Clears the persisted first-run flag at launch so every test starts
        // from the same state, independent of what an earlier test left behind.
        app.launchArguments = ["-uitest-reset-onboarding"]
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    // MARK: - Baseline

    func testOnboardingRendersAndContinueIsUsableAtDefaultSize() {
        let app = launchAtOnboarding(contentSize: nil)

        XCTAssertTrue(
            app.staticTexts["Swipe Through Your Library"].waitForExistence(timeout: timeout),
            "the first onboarding page should render on a fresh launch"
        )

        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: timeout))
        XCTAssertTrue(continueButton.isHittable)
    }

    // MARK: - Accessibility sizes

    /// The headline regression: at the largest text size the first page's copy
    /// and its button must both remain on screen and reachable.
    func testFirstPageStaysUsableAtLargestTextSize() {
        let app = launchAtOnboarding(contentSize: Self.accessibilityXXXL)

        XCTAssertTrue(
            app.staticTexts["Swipe Through Your Library"].waitForExistence(timeout: timeout),
            "the title must not be pushed off screen by the scaled glyph"
        )

        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: timeout))
        XCTAssertTrue(
            continueButton.isHittable,
            "Continue must stay reachable at Accessibility XXXL"
        )
    }

    /// Walks to the permission primer — the page whose button is the one-shot
    /// system prompt, so an unreachable button there costs the user the prompt.
    func testPermissionPrimerButtonIsReachableAtLargestTextSize() {
        let app = launchAtOnboarding(contentSize: Self.accessibilityXXXL)

        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: timeout))
        continueButton.tap()

        XCTAssertTrue(
            app.staticTexts["Nothing Leaves Your Device"].waitForExistence(timeout: timeout),
            "page two should be showing"
        )
        app.buttons["Continue"].tap()

        XCTAssertTrue(
            app.staticTexts["Access to Your Photos"].waitForExistence(timeout: timeout),
            "page three should be showing"
        )

        // Scoped by identifier: the permission gate behind this cover renders
        // its own "Allow Access" button, which must not satisfy this query.
        let allowButton = app.buttons["onboardingPrimaryButton"]
        XCTAssertTrue(allowButton.waitForExistence(timeout: timeout))
        XCTAssertEqual(allowButton.label, "Allow Access")
        XCTAssertTrue(
            allowButton.isHittable,
            "the primer's Allow Access button must stay reachable at Accessibility XXXL — it is the only route to the system prompt"
        )
    }

    /// Skip must work at every text size: it is the escape hatch for a user who
    /// does not want to read three pages.
    func testSkipDismissesOnboardingAtLargestTextSize() {
        let app = launchAtOnboarding(contentSize: Self.accessibilityXXXL)

        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: timeout))
        XCTAssertTrue(skip.isHittable, "Skip must stay reachable at Accessibility XXXL")
        skip.tap()

        // The onboarding cover is gone once Skip lands. The gate then renders
        // either the tab bar (access already granted) or the permission screen,
        // so assert the cover itself is what disappeared.
        let coverGone = NSPredicate(format: "exists == false")
        expectation(for: coverGone, evaluatedWith: app.staticTexts["Swipe Through Your Library"])
        waitForExpectations(timeout: timeout)
    }
}
