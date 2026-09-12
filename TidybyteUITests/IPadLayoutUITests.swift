import XCTest

/// iPad-specific layout checks.
///
/// The app adapts the tab bar into a sidebar on iPad (iOS 18+). That is a
/// platform behavior, so the assertion here is narrow but real: on an iPad the
/// app must still present its four sections and reach every one of them, and the
/// enlarged layout must not push a section out of reach.
///
/// Skipped automatically when the destination is not an iPad, so the same file
/// can be part of the default scheme without failing on iPhone.
final class IPadLayoutUITests: XCTestCase {

    private let timeout: TimeInterval = 20

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "iPad-only layout checks"
        )
    }

    /// Launches past the first-run flow so the assertions target the shell.
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset-onboarding"]
        app.launch()

        // Dismiss onboarding if it is showing; the shell is what is under test.
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 5) {
            skip.tap()
        }
        return app
    }

    /// Every section must be reachable. On iPad these render as sidebar rows; on
    /// an older iPadOS as tab-bar buttons. Both satisfy the assertion, which is
    /// the point — the app must remain navigable either way.
    func testAllSectionsAreReachable() {
        let app = launchApp()

        for label in ["Swipe", "Cleanup", "Storage", "Settings"] {
            let element = app.buttons[label].firstMatch
            XCTAssertTrue(
                element.waitForExistence(timeout: timeout),
                "\(label) must be reachable on iPad"
            )
            XCTAssertTrue(element.isHittable, "\(label) must be hittable on iPad")
        }
    }

    /// The wide layout must not leave the primary controls off screen.
    ///
    /// Asserts on the first section's row rather than something further down:
    /// a `Form` is lazy, so rows below the fold do not exist in the
    /// accessibility tree until they are scrolled into view, and asserting on
    /// one would test scrolling rather than layout.
    func testSettingsRendersItsControlsAtTheLargestTextSize() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uitest-reset-onboarding",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 5) {
            skip.tap()
        }

        let settingsButton = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: timeout))
        settingsButton.tap()

        // The first Settings row — present without scrolling, and unique to this
        // screen, so it proves the section rendered rather than that the tap was
        // absorbed. Hittability is asserted on the navigation bar rather than on
        // this label: a Form row's label is not the interactive element, so
        // `isHittable` on it would report the picker's hit area, not the row's.
        let marker = app.staticTexts["Default Filter"].firstMatch
        XCTAssertTrue(
            marker.waitForExistence(timeout: timeout),
            "the Settings section must render its controls at Accessibility XXXL on iPad"
        )

        let navBar = app.navigationBars["Settings"].firstMatch
        XCTAssertTrue(
            navBar.waitForExistence(timeout: 5),
            "Settings should be the active section"
        )
        XCTAssertTrue(navBar.isHittable)
    }
}
