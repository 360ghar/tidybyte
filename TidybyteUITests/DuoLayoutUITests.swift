import XCTest

/// Resizability tripwires for iPhone Duo and any resizable window.
///
/// iPhone Duo (foldable, iOS 27.1) has two displays — outer 466×678 pt, inner
/// 669×951 pt — can present the system bars *vertically* on a side edge, and can
/// resize the window at any moment. Nothing here needs the Duo runtime: every
/// assertion is device-agnostic, so it passes on an ordinary iPhone and an iPad
/// today and turns red the day a layout stops surviving a resizable window.
/// Geometry, not idiom: `userInterfaceIdiom` no longer identifies the device.
final class DuoLayoutUITests: XCTestCase {

    private let timeout: TimeInterval = 20

    /// The two known Duo poses, in points, matched within ±2 pt.
    private static let duoPoses: [(name: String, size: CGSize)] = [
        ("outer 466×678", CGSize(width: 466, height: 678)),
        ("inner 669×951", CGSize(width: 669, height: 951)),
    ]

    /// Controls that legitimately sit inside the edge band. The band proxies
    /// "a vertical system bar may be covering this"; the tab bar and the
    /// navigation/toolbar are placed and inset by the system, so an item there
    /// is not evidence of an app layout bug.
    private static let edgeBandAllowlist: Set<String> = ["tabItem", "toolbar"]

    /// A vertical system bar can only exist on a window this wide. On a compact
    /// portrait iPhone (≈402 pt) there is no side bar and the app's own 16 pt
    /// content margin is narrower than the 8% band (32 pt), so every full-width
    /// row trips it — a false positive. Below this width the test asserts the
    /// resizability property that still applies: nothing is clipped.
    private static let edgeBandApplicableMinimumWidth: CGFloat = 600

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Launch

    /// Launches the shell, optionally granting photo access. Mirrors
    /// `CleanupFeaturesUITests`: the system Photos prompt is reset and answered
    /// so the cleanup tools can be driven. Pinned to English for the labels.
    private func launch(grantPhotos: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        if grantPhotos {
            app.resetAuthorizationStatus(for: .photos)
            addUIInterruptionMonitor(withDescription: "Photos access") { alert in
                let allow = alert.buttons.matching(NSPredicate(
                    format: "label CONTAINS[c] 'Allow' AND (label CONTAINS[c] 'Full' OR label CONTAINS[c] 'All Photos')"
                )).firstMatch
                guard allow.exists else { return false }
                allow.tap()
                return true
            }
        }
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launchArguments += DynamicTypeUITests.englishLaunchArguments
        app.launch()

        guard grantPhotos else { return app }
        // Answer the in-app permission gate and the system alert behind it. A
        // delayed alert needs an interaction to invoke the interruption handler.
        let allowAccess = app.buttons["Allow Access"].firstMatch
        XCTAssertTrue(allowAccess.waitForExistence(timeout: 15), "the permission gate must appear")
        for _ in 0..<6 where !allowAccess.isHittable { app.swipeUp() }
        allowAccess.tap()
        for _ in 0..<10 {
            if allowAccess.waitForNonExistence(timeout: 1) { break }
            app.buttons["Swipe"].firstMatch.tap()
        }
        XCTAssertFalse(allowAccess.exists, "Photos access must be granted before driving the cleanup tools.")
        return app
    }

    // MARK: - Geometry helpers

    private func window(of app: XCUIApplication) -> CGRect {
        let win = app.windows.firstMatch
        XCTAssertTrue(win.waitForExistence(timeout: timeout), "the app window must exist")
        return win.frame
    }

    /// Names the Duo pose this window matches, if any, so a red test says which
    /// pose tripped it.
    private func poseContext(_ window: CGRect) -> String {
        let pose = Self.duoPoses.first {
            abs($0.size.width - window.width) <= 2 && abs($0.size.height - window.height) <= 2
        }?.name ?? "no known Duo pose"
        return "window \(Int(window.width))×\(Int(window.height)) pt (\(pose))"
    }

    /// Interactive controls whose frame intersects the leading or trailing edge
    /// band (`min(width, height) * 0.08`). Candidates are deduplicated by
    /// label+frame, deliberately without the kind: the same element is reachable
    /// through `app.tabBars.buttons` and again through `app.buttons`, and the
    /// collection order below visits the more specific containers first, so the
    /// allowlisted `tabItem` classification wins. Keying on the kind stored the
    /// plain `button` copy as a second candidate, which is not allowlisted and
    /// failed the band check on a control this test means to exempt.
    private func edgeBandViolations(in app: XCUIApplication, window: CGRect) -> [String] {
        let band = min(window.width, window.height) * 0.08
        let leading = CGRect(x: window.minX, y: window.minY, width: band, height: window.height)
        let trailing = CGRect(x: window.maxX - band, y: window.minY, width: band, height: window.height)

        var candidates: [(kind: String, label: String, frame: CGRect)] = []
        var seen = Set<String>()
        func collect(_ element: XCUIElement, kind: String) {
            guard element.exists else { return }
            let frame = element.frame
            guard !frame.isEmpty, frame.intersects(window) else { return }
            guard seen.insert("\(element.label)|\(frame)").inserted else { return }
            candidates.append((kind, element.label, frame))
        }
        app.tabBars.buttons.allElementsBoundByIndex.forEach { collect($0, kind: "tabItem") }
        app.navigationBars.buttons.allElementsBoundByIndex.forEach { collect($0, kind: "toolbar") }
        app.buttons.allElementsBoundByIndex.forEach { collect($0, kind: "button") }

        return candidates
            .filter { !Self.edgeBandAllowlist.contains($0.kind) }
            .filter { $0.frame.intersects(leading) || $0.frame.intersects(trailing) }
            .map { "\($0.kind) \"\($0.label)\" at \($0.frame) is inside the \(Int(band)) pt edge band" }
    }

    /// Fixed chrome whose frame extends past the window — clipped on any pose.
    /// Scrollable content is excluded: a row half-scrolled off the bottom edge
    /// is not a layout bug.
    private func clippingViolations(in app: XCUIApplication, window: CGRect) -> [String] {
        var violations: [String] = []
        func check(_ element: XCUIElement, kind: String) {
            guard element.exists else { return }
            let frame = element.frame
            guard !frame.isEmpty else { return }
            if frame.minX < window.minX - 1 || frame.maxX > window.maxX + 1
                || frame.minY < window.minY - 1 || frame.maxY > window.maxY + 1 {
                violations.append("\(kind) \"\(element.label)\" at \(frame) is clipped by the window \(window)")
            }
        }
        app.tabBars.buttons.allElementsBoundByIndex.forEach { check($0, kind: "tabItem") }
        app.navigationBars.buttons.allElementsBoundByIndex.forEach { check($0, kind: "toolbar") }
        return violations
    }

    // MARK: - 1. Window sanity

    /// The window must be real, and the shell must lay out inside it.
    func testWindowIsNonDegenerateAndPoseIsRecorded() {
        let app = launch(grantPhotos: false)
        let win = window(of: app)

        XCTAssertGreaterThanOrEqual(win.width, 200, "window must be at least a phone width — \(poseContext(win))")
        XCTAssertGreaterThanOrEqual(win.height, 200, "window must be at least a phone height — \(poseContext(win))")

        let swipe = app.buttons["Swipe"].firstMatch
        XCTAssertTrue(swipe.waitForExistence(timeout: timeout), "the shell must render — \(poseContext(win))")
        XCTAssertTrue(
            win.intersects(swipe.frame),
            "the first section must be laid out within the window frame — \(poseContext(win))"
        )
    }

    // MARK: - 2. Tab items contained

    /// Every section must exist, be tappable, and sit inside the window. A tab
    /// bar shoved under a vertical system bar fails the containment check.
    func testAllSectionsAreContainedInTheWindow() {
        let app = launch(grantPhotos: false)
        let win = window(of: app)

        for label in ["Swipe", "Cleanup", "Storage", "Settings"] {
            let item = app.buttons[label].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: timeout), "\(label) must exist — \(poseContext(win))")
            XCTAssertTrue(item.isHittable, "\(label) must be hittable — \(poseContext(win))")
            let f = item.frame
            XCTAssertTrue(
                f.minX >= win.minX - 1 && f.maxX <= win.maxX + 1 && f.minY >= win.minY - 1 && f.maxY <= win.maxY + 1,
                "\(label) at \(f) must be contained in the window \(win) — \(poseContext(win))"
            )
        }
    }

    // MARK: - 3. Edge-band clearance

    /// No interactive control may intrude into the leading/trailing edge band —
    /// the cheap proxy for "a vertical system bar is sitting on top of me".
    /// Scoped to wide windows, where a vertical bar can exist; see
    /// `edgeBandApplicableMinimumWidth`.
    func testNoControlIntrudesIntoTheEdgeBand() {
        let app = launch(grantPhotos: false)
        let win = window(of: app)
        XCTAssertTrue(app.buttons["Swipe"].firstMatch.waitForExistence(timeout: timeout), "the shell must render")

        let wide = win.width >= Self.edgeBandApplicableMinimumWidth
        let violations = wide ? edgeBandViolations(in: app, window: win) : clippingViolations(in: app, window: win)
        let what = wide ? "controls intrude into the edge band" : "chrome is clipped by the window"
        XCTAssertTrue(violations.isEmpty, "\(what) — \(poseContext(win)):\n" + violations.joined(separator: "\n"))
    }

    // MARK: - 4. Sheet containment

    /// A presented sheet must stay inside the window on every display size.
    func testChatAlbumSheetStaysInsideTheWindow() {
        let app = launch(grantPhotos: true)
        let win = window(of: app)

        let cleanup = app.buttons["Cleanup"].firstMatch
        XCTAssertTrue(cleanup.waitForExistence(timeout: timeout))
        cleanup.tap()

        let tool = app.descendants(matching: .any).matching(identifier: "cleanup.chatMedia").firstMatch
        for _ in 0..<8 {
            if tool.waitForExistence(timeout: 1) && tool.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(tool.exists && tool.isHittable, app.debugDescription)
        tool.tap()

        let albums = app.buttons["Albums"].firstMatch
        XCTAssertTrue(albums.waitForExistence(timeout: 15), "the Albums toolbar button must exist")
        albums.tap()

        let sheetTitle = app.navigationBars["Chat albums"].firstMatch
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: 15), "the album sheet must present")

        // The sheet's own container when the platform exposes one; otherwise its
        // navigation bar, which is laid out at the sheet's top edge and is just
        // as good a proof that the sheet did not overhang.
        let sheet = app.sheets.firstMatch
        let container = sheet.exists ? sheet.frame : sheetTitle.frame
        XCTAssertFalse(container.isEmpty, "the presented sheet must have a real frame")

        XCTAssertGreaterThanOrEqual(container.minX, win.minX - 1, "sheet must not overhang the leading edge — \(poseContext(win))")
        XCTAssertGreaterThanOrEqual(container.minY, win.minY - 1, "sheet must not overhang the top edge — \(poseContext(win))")
        XCTAssertLessThanOrEqual(container.maxX, win.maxX + 1, "sheet must not overhang the trailing edge — \(poseContext(win))")
        XCTAssertLessThanOrEqual(container.maxY, win.maxY + 1, "sheet must not overhang the bottom edge — \(poseContext(win))")
    }
}
