import XCTest

/// Uses the system Photos prompt. No media is deleted.
@MainActor
final class CleanupFeaturesUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .photos)
        addUIInterruptionMonitor(withDescription: "Photos access") { alert in
            let allow = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Allow' AND (label CONTAINS[c] 'Full' OR label CONTAINS[c] 'All Photos')")).firstMatch
            guard allow.exists else { return false }
            allow.tap()
            return true
        }
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let allowAccess = app.buttons["Allow Access"].firstMatch
        XCTAssertTrue(allowAccess.waitForExistence(timeout: 15))
        for _ in 0..<6 {
            if allowAccess.isHittable { break }
            app.swipeUp()
        }
        allowAccess.tap()
        // A delayed prompt needs an interaction to invoke the interruption handler.
        // An existence wait alone cannot handle an alert that arrives after the tap.
        for _ in 0..<10 {
            if allowAccess.waitForNonExistence(timeout: 1) { break }
            app.buttons["Swipe"].firstMatch.tap()
        }
        XCTAssertFalse(allowAccess.exists, "Photos access must be granted before testing cleanup tools.")
        return app
    }

    private func openTool(_ id: String, in app: XCUIApplication) throws {
        let cleanup = app.buttons["Cleanup"].firstMatch
        XCTAssertTrue(cleanup.waitForExistence(timeout: 15))
        cleanup.tap()
        let tool = app.descendants(matching: .any).matching(identifier: "cleanup.\(id)").firstMatch
        for _ in 0..<8 {
            if tool.waitForExistence(timeout: 1) && tool.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(tool.exists, app.debugDescription)
        XCTAssertTrue(tool.isHittable)
        tool.tap()
    }

    func testScreenRecordingsOpensAtLargestTextSize() throws {
        let app = launch()
        try openTool("screenRecordings", in: app)
        XCTAssertTrue(app.navigationBars["Screen Recordings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["mediaSort"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["mediaSort"].firstMatch.isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testChatAlbumPickerRemainsReachableAtLargestTextSize() throws {
        let app = launch()
        try openTool("chatMedia", in: app)
        let albums = app.buttons["Albums"].firstMatch
        XCTAssertTrue(albums.waitForExistence(timeout: 10))
        XCTAssertTrue(albums.isHittable)
        albums.tap()
        XCTAssertTrue(app.navigationBars["Chat albums"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Done"].isHittable)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(albums.isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testWorstShotsFilterIsReachable() throws {
        guard #available(iOS 18, *) else { throw XCTSkip("Worst Shots requires iOS 18 or later.") }
        let app = launch()
        let filter = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Worst Shots")).firstMatch
        for _ in 0..<4 {
            if filter.exists && filter.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(filter.exists)
        XCTAssertTrue(filter.isHittable)
    }
}
