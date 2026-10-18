import XCTest

/// Proves a language switch is live and non-destructive, which is the pair of
/// claims the `.id(languageStore.effectiveLanguage)` removal rests on.
///
/// `RootView` used to key the whole tree on the language, which forced a
/// rebuild: it destroyed child `@State` (a live swipe session's view model, with
/// deletions marked but not committed) rather than just re-rendering text. With
/// the key gone, two things have to hold at once:
///
/// 1. text built in code (`Text(tool.name)`, a computed `String` resolved
///    through `L10n`) re-resolves without a relaunch, and
/// 2. the screen the user was on is still there afterwards.
///
/// They are two tests rather than one flow because the second one leaves the app
/// on a pushed screen, and splitting means a failure names which half broke.
///
/// A third test covers the launch reset the other two depend on: it must clear a
/// stored language before the app reads it, or every English assertion here
/// starts from a German app.
///
/// English and German are used because both ship, the German strings differ
/// from the English ones, and the endonyms in the picker are never translated.
@MainActor
final class LanguageSwitchUITests: XCTestCase {

    private let timeout: TimeInterval = 30

    /// German for the strings asserted below. Literal, so a translation change
    /// fails here loudly instead of silently asserting the English text twice.
    private static let germanCleanupTab = "Bereinigung"
    private static let germanSettingsTitle = "Einstellungen"
    private static let germanDuplicates = "Duplikate"
    /// The German of the Duplicates tool's idle headline, the catalog key
    /// "Find Duplicate Photos". Read from the running app, so it proves the
    /// pushed screen re-rendered rather than merely still existing.
    private static let germanDuplicatesIdleHeadline = "Duplikate finden"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        // The pick is persisted in the App Group, and the other UI test classes
        // pin English with `-AppleLanguages`, which the stored override
        // outranks. Launch once with the reset argument so the key is cleared
        // even when this test failed halfway through, then quit.
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset-onboarding"]
        app.launch()
        app.terminate()
        super.tearDown()
    }

    // MARK: - Launch

    /// Launches with photo access granted, because the Cleanup grid the test
    /// drives only renders behind the permission gate.
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .photos)
        addUIInterruptionMonitor(withDescription: "Photos access") { alert in
            let allow = alert.buttons.matching(NSPredicate(
                format: "label CONTAINS[c] 'Allow' AND (label CONTAINS[c] 'Full' OR label CONTAINS[c] 'All Photos')"
            )).firstMatch
            guard allow.exists else { return false }
            allow.tap()
            return true
        }
        // The reset also clears a language left stored by an earlier run, so the
        // English baseline below cannot be broken by one.
        app.launchArguments = ["-uitest-reset-onboarding"]
        app.launchArguments += DynamicTypeUITests.englishLaunchArguments
        app.launch()

        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: timeout), "onboarding must be showing on a reset launch")
        skip.tap()

        let allowAccess = app.buttons["Allow Access"].firstMatch
        XCTAssertTrue(allowAccess.waitForExistence(timeout: timeout), "the permission gate must appear")
        for _ in 0..<6 where !allowAccess.isHittable { app.swipeUp() }
        allowAccess.tap()
        // A delayed system prompt needs an interaction to invoke the
        // interruption handler above; an existence wait alone cannot catch an
        // alert that arrives after the tap.
        for _ in 0..<10 {
            if allowAccess.waitForNonExistence(timeout: 1) { break }
            app.buttons["Swipe"].firstMatch.tap()
        }
        XCTAssertFalse(allowAccess.exists, "Photos access must be granted before driving the Cleanup grid")
        return app
    }

    // MARK: - Helpers

    /// The tab bar's own button. Scoped to the tab bar where possible, because
    /// a pushed screen's back button carries the same label as its tab.
    private func tabButton(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let inTabBar = app.tabBars.buttons[label]
        return inTabBar.exists ? inTabBar : app.buttons[label].firstMatch
    }

    /// A tool card on the Cleanup grid.
    ///
    /// Queried through `descendants(matching: .any)`, not `app.buttons`: the card
    /// sets `.accessibilityElement(children: .ignore)` and then adds the button
    /// trait, which makes the platform publish it as an `.other` element that
    /// merely *carries* the trait. A `buttons` query never matches it. The other
    /// Cleanup suites query it the same way for the same reason.
    private func toolCard(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "cleanup.\(id)").firstMatch
    }

    /// Scrolls the grid until the card is reachable. It is a `LazyVGrid`, so a
    /// card below the fold does not exist in the hierarchy until it is scrolled
    /// into range, and `waitForExistence` alone cannot find it.
    private func revealTool(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let card = toolCard(id, in: app)
        for _ in 0..<8 {
            if card.waitForExistence(timeout: 1) && card.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(card.exists, "the \(id) card must be in the grid: \(app.debugDescription)")
        XCTAssertTrue(card.isHittable, "the \(id) card must be reachable: \(app.debugDescription)")
        return card
    }

    /// Selects a language in the Settings picker.
    ///
    /// The picker's style is the platform default, so its options can arrive as
    /// a pushed list or as a menu; both are queried. Endonyms are never
    /// translated, so the same label works in any UI language.
    private func selectLanguage(_ endonym: String, in app: XCUIApplication) {
        let picker = app.descendants(matching: .any).matching(identifier: "settings.language").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: timeout), "the language picker must be on the Settings screen")
        for _ in 0..<6 where !picker.isHittable { app.swipeUp() }
        picker.tap()

        let asButton = app.buttons[endonym].firstMatch
        if asButton.waitForExistence(timeout: 5) {
            asButton.tap()
            return
        }
        let asText = app.staticTexts[endonym].firstMatch
        XCTAssertTrue(asText.waitForExistence(timeout: 5), "the \(endonym) row must be offered")
        asText.tap()
    }

    // MARK: - The flow

    /// Claim 1: the Cleanup grid's tool name is built in code, and it re-resolves
    /// in place. This is the string the `.id` key was added for.
    func testSwitchingLanguageRerendersCodeBuiltTextInPlace() {
        let app = launch()

        // 1. English baseline on the Cleanup grid.
        tabButton("Cleanup", in: app).tap()
        let englishCard = revealTool("duplicates", in: app)
        XCTAssertTrue(
            englishCard.label.contains("Duplicates"),
            "the English tool name must be on the card before the switch: \(englishCard.label)"
        )

        // 2. Switch to German from Settings.
        switchToGerman(in: app)

        // 3. Back on the grid, the code-built tool name re-resolved live.
        tabButton(Self.germanCleanupTab, in: app).tap()
        let germanCard = revealTool("duplicates", in: app)
        XCTAssertTrue(
            germanCard.label.contains(Self.germanDuplicates),
            "the tool name is built in code and must re-resolve without a relaunch: \(germanCard.label)"
        )

        // 4. Nothing reset: no onboarding cover, tab bar still responsive.
        XCTAssertFalse(
            app.staticTexts["Swipe Through Your Library"].exists,
            "onboarding must not reappear, which is what a reset tree would show"
        )
        XCTAssertTrue(tabButton(Self.germanCleanupTab, in: app).isHittable, "the tab bar must stay responsive")
    }

    /// Claim 2: a language switch does not tear down what is on screen. The
    /// pushed tool screen is the cheapest stand-in for the state that used to be
    /// destroyed, and it is the one a tree rebuild would visibly cost.
    func testSwitchingLanguageKeepsThePushedScreen() {
        let app = launch()

        // 1. Push a tool so there is a navigation stack to lose.
        tabButton("Cleanup", in: app).tap()
        revealTool("duplicates", in: app).tap()
        XCTAssertTrue(
            app.navigationBars["Duplicates"].waitForExistence(timeout: timeout),
            "the Duplicates tool must be pushed before the language changes"
        )

        // 2. Switch to German from Settings.
        switchToGerman(in: app)

        // 3. Back on the Cleanup tab the pushed screen is still pushed, and both
        //    its bar and its body re-resolved. A tree rebuild is what used to
        //    cost that screen.
        //
        //    The bar is the assertion that matters most: it is UIKit-backed and
        //    only re-applies a title whose *value* changed, so it is the surface
        //    a stale key leaves behind — this screen's body does not run again
        //    for a language change, so a title passed as the same
        //    `LocalizedStringKey` in both languages kept the old one. Every
        //    `.navigationTitle` call site resolves through `L10n.string` for
        //    exactly this reason.
        tabButton(Self.germanCleanupTab, in: app).tap()
        XCTAssertTrue(
            app.buttons["BackButton"].waitForExistence(timeout: timeout),
            "the pushed tool screen must survive the language change: \(app.debugDescription)"
        )
        XCTAssertTrue(
            app.navigationBars[Self.germanDuplicates].waitForExistence(timeout: timeout),
            "the pushed screen's title must re-resolve in place: \(app.debugDescription)"
        )
        XCTAssertTrue(
            app.staticTexts[Self.germanDuplicatesIdleHeadline].waitForExistence(timeout: timeout),
            "the pushed screen must re-render its German copy: \(app.debugDescription)"
        )
    }

    /// The launch reset must clear a stored language *before* the app reads it.
    ///
    /// `RootView` builds its `LanguageStore` in a property initializer, and a
    /// property initializer runs before the body of its own `init`. A reset
    /// performed in that body therefore cleared storage too late for the launch
    /// it targeted: `LanguageStore` had already read the previous language, the
    /// whole app rendered in it, and only the *next* launch saw the clear. Every
    /// English assertion in this class then starts from a German app.
    ///
    /// This drives that exact sequence, which is why it deliberately ends one
    /// launch in German without cleaning up.
    func testResetLaunchDoesNotInheritThePreviousLanguage() {
        // 1. A launch that ends in German, left stored on purpose.
        let german = launch()
        switchToGerman(in: german)
        german.terminate()

        // 2. The reset launch. `-hasCompletedOnboarding YES` keeps the cover
        //    down (an argument-domain value outranks the write the reset makes),
        //    and photo access was granted in step 1 and persists, so the tab bar
        //    is on screen without walking the gate again.
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-uitest-reset-onboarding", "-hasCompletedOnboarding", "YES"]
        relaunched.launchArguments += DynamicTypeUITests.englishLaunchArguments
        relaunched.launch()

        // Asserted through `tabButton`, not `app.tabBars.buttons` directly: on
        // this destination the tab bar is not always published as a `TabBar`
        // element, and the helper falls back to a plain button lookup for that
        // reason. Either way the label is English only if the reset worked.
        XCTAssertTrue(
            tabButton("Cleanup", in: relaunched).waitForExistence(timeout: timeout),
            "a reset launch must not inherit the language the previous launch stored: \(relaunched.debugDescription)"
        )
    }

    /// Walks Settings and picks German, asserting the switch took effect there
    /// before returning. Shared by both tests so the German assertions cannot
    /// drift apart.
    private func switchToGerman(in app: XCUIApplication) {
        tabButton("Settings", in: app).tap()
        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: timeout),
            "the Settings screen must be showing"
        )
        selectLanguage("Deutsch", in: app)
        XCTAssertTrue(
            app.navigationBars[Self.germanSettingsTitle].waitForExistence(timeout: timeout),
            "Settings must re-render in German in place: \(app.debugDescription)"
        )
    }
}
