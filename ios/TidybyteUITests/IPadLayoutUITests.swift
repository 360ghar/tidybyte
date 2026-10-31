import XCTest

/// Wide-layout checks for iPad and any wide iPhone.
///
/// The app adapts the tab bar into a sidebar on iPad (iOS 18+). That is a
/// platform behavior, so the assertion here is narrow but real: on a wide
/// layout the app must still present its four sections and reach every one of
/// them, and the enlarged layout must not push a section out of reach.
///
/// The gate is *geometry*, not idiom. Apple's guidance for iPhone Duo (a
/// foldable iPhone, iOS 27.1) is that `userInterfaceIdiom` no longer identifies
/// the device: the inner display is a wide, regular-width layout behind an
/// idiom of `.phone`. Gating on the actual window width means this test runs on
/// iPad AND on a Duo inner display, and skips an ordinary narrow iPhone — which
/// is exactly the set of destinations this layout must hold on.
///
/// The threshold sits between the widest compact iPhone and the narrowest wide
/// layout: Duo outer is 466 pt (compact, skipped), Duo inner is 669 pt (wide,
/// runs), the narrowest modern iPad is 744 pt (wide, runs).
final class IPadLayoutUITests: XCTestCase {

    private let timeout: TimeInterval = 20

    /// The window must be at least this wide to exercise the wide layout.
    private static let wideLayoutMinimumWidth: CGFloat = 600

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        // The skip lives in `launchApp` rather than here: the gate is the width
        // of the *launched app's window*, and no window exists before launch.
    }

    /// Launches past the first-run flow so the assertions target the shell.
    ///
    /// Pinned to English: the assertions below match English tab labels, and
    /// the app follows the device language by default. See
    /// `DynamicTypeUITests.englishLaunchArguments`.
    ///
    /// Skips when the launched window is too narrow to exercise the wide layout,
    /// so the same file can be part of the default scheme without failing on an
    /// ordinary iPhone. The gate reads the real window width rather than the
    /// device idiom, which is what makes it correct on iPhone Duo: the inner
    /// display is a wide, regular-width layout whose idiom is still `.phone`.
    private func launchApp() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset-onboarding"]
        app.launchArguments += DynamicTypeUITests.englishLaunchArguments
        app.launch()

        // Dismiss onboarding if it is showing; the shell is what is under test.
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 5) {
            skip.tap()
        }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: timeout), "the app window must exist")
        try XCTSkipUnless(
            window.frame.width >= Self.wideLayoutMinimumWidth,
            "wide-layout-only check: window width \(window.frame.width) pt is below the \(Self.wideLayoutMinimumWidth) pt threshold"
        )
        return app
    }

    /// Every section must be reachable. On a wide layout these render as sidebar
    /// rows; on an older iPadOS as tab-bar buttons. Both satisfy the assertion,
    /// which is the point — the app must remain navigable either way.
    func testAllSectionsAreReachable() throws {
        let app = try launchApp()

        for label in ["Swipe", "Cleanup", "Storage", "Settings"] {
            let element = app.buttons[label].firstMatch
            XCTAssertTrue(
                element.waitForExistence(timeout: timeout),
                "\(label) must be reachable in the wide layout"
            )
            XCTAssertTrue(element.isHittable, "\(label) must be hittable in the wide layout")
        }
    }

    /// The wide layout must not leave the primary controls off screen.
    ///
    /// Asserts on the first section's row rather than something further down:
    /// a `Form` is lazy, so rows below the fold do not exist in the
    /// accessibility tree until they are scrolled into view, and asserting on
    /// one would test scrolling rather than layout.
    func testSettingsRendersItsControlsAtTheLargestTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uitest-reset-onboarding",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launchArguments += DynamicTypeUITests.englishLaunchArguments
        app.launch()

        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 5) {
            skip.tap()
        }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: timeout), "the app window must exist")
        try XCTSkipUnless(
            window.frame.width >= Self.wideLayoutMinimumWidth,
            "wide-layout-only check: window width \(window.frame.width) pt is below the \(Self.wideLayoutMinimumWidth) pt threshold"
        )

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
            "the Settings section must render its controls at Accessibility XXXL in the wide layout"
        )

        let navBar = app.navigationBars["Settings"].firstMatch
        XCTAssertTrue(
            navBar.waitForExistence(timeout: 5),
            "Settings should be the active section"
        )
        XCTAssertTrue(navBar.isHittable)
    }
}
