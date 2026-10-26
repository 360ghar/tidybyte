import XCTest
@testable import Tidybyte

/// Pins the happy-path rating-prompt policy: only on milestones (3, 10, 25,
/// then every 50th), throttled to once per 60 days, never before the user has
/// done anything, and never again once the user has rated.
final class ReviewPromptGateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ReviewPromptGateTests.\(UUID().uuidString)"
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

    private func day(_ days: Int, before now: Date) -> Date {
        now.addingTimeInterval(TimeInterval(-days * 24 * 60 * 60))
    }

    func testFirstSuccessPrompts() {
        let now = Date()
        // The first fully successful cleanup is the honest ask: the user just
        // saw space come back, and a session that ends before a third success
        // would otherwise never be asked.
        XCTAssertTrue(AppPreferences.shouldRequestReview(successCount: 1, lastPromptAt: nil, now: now))
        // Still a one-shot: a never-rated user is not asked again the next day.
        XCTAssertFalse(AppPreferences.shouldRequestReview(successCount: 2, lastPromptAt: now, now: now))
    }

    func testBetweenMilestonesNeverPrompt() {
        let now = Date()
        for count in [2, 3, 4, 5, 6, 7, 8, 9, 11, 24, 26, 49] {
            XCTAssertFalse(
                AppPreferences.shouldRequestReview(successCount: count, lastPromptAt: nil, now: now),
                "count \(count) must not prompt"
            )
        }
    }

    func testEveryFiftiethCountsAsMilestone() {
        let now = Date()
        XCTAssertTrue(AppPreferences.shouldRequestReview(successCount: 50, lastPromptAt: nil, now: now))
        XCTAssertTrue(AppPreferences.shouldRequestReview(successCount: 100, lastPromptAt: nil, now: now))
    }

    func testZeroActionsNeverPrompt() {
        let now = Date()
        XCTAssertFalse(AppPreferences.shouldRequestReview(successCount: 0, lastPromptAt: nil, now: now))
    }

    func testCooldownBlocksLaterMilestones() {
        let now = Date()
        let promptedFiveDaysAgo = day(5, before: now)
        // 10 is a milestone, but the prompt at 3 was only 5 days ago.
        XCTAssertFalse(AppPreferences.shouldRequestReview(successCount: 10, lastPromptAt: promptedFiveDaysAgo, now: now))
        // Same milestone once the 60-day cooldown has elapsed.
        let promptedSixtyOneDaysAgo = day(61, before: now)
        XCTAssertTrue(AppPreferences.shouldRequestReview(successCount: 10, lastPromptAt: promptedSixtyOneDaysAgo, now: now))
        // 59 days and 23 hours is still inside the cooldown.
        let almost = now.addingTimeInterval(TimeInterval(-60 * 24 * 60 * 60 + 3600))
        XCTAssertFalse(AppPreferences.shouldRequestReview(successCount: 10, lastPromptAt: almost, now: now))
    }

    func testRecordSuccessfulActionCountsAndPersists() {
        let now = Date()
        XCTAssertEqual(AppPreferences.successfulActionCount(in: defaults), 0)
        XCTAssertTrue(AppPreferences.recordSuccessfulAction(now: now, in: defaults))
        XCTAssertFalse(AppPreferences.recordSuccessfulAction(now: now, in: defaults))
        XCTAssertFalse(AppPreferences.recordSuccessfulAction(now: now, in: defaults))
        XCTAssertEqual(AppPreferences.successfulActionCount(in: defaults), 3)
    }

    func testRecordedPromptDateConsumesCooldown() {
        let now = Date()
        // The first success is the milestone; record its prompt date.
        XCTAssertTrue(AppPreferences.recordSuccessfulAction(now: now, in: defaults))
        AppPreferences.recordReviewPromptDate(now, in: defaults)

        // 2-9 are not milestones; 10 is one, but it falls inside the cooldown,
        // so every action in this run stays silent.
        for _ in 0..<9 {
            XCTAssertFalse(AppPreferences.recordSuccessfulAction(now: now, in: defaults))
        }
        XCTAssertEqual(AppPreferences.successfulActionCount(in: defaults), 10)

        // Simulate the user cleaning on: milestones fire again only once 60
        // days have passed since the last prompt — next up is 25, then 50.
        var date = now
        var firedCounts: [Int] = []
        while AppPreferences.successfulActionCount(in: defaults) < 60 {
            date = date.addingTimeInterval(TimeInterval(10 * 24 * 60 * 60))
            if AppPreferences.recordSuccessfulAction(now: date, in: defaults) {
                firedCounts.append(AppPreferences.successfulActionCount(in: defaults))
            }
        }
        XCTAssertEqual(firedCounts, [25, 50])
    }

    func testRatedUserIsNeverPrompted() {
        let now = Date()
        XCTAssertFalse(AppPreferences.shouldRequestReview(successCount: 1, lastPromptAt: nil, hasRated: true, now: now))
        XCTAssertFalse(AppPreferences.shouldRequestReview(successCount: 50, lastPromptAt: nil, hasRated: true, now: now))
    }

    func testRatedFlagSilencesEveryMilestoneButKeepsCounting() {
        XCTAssertFalse(AppPreferences.hasRatedApp(in: defaults))
        AppPreferences.saveHasRatedApp(in: defaults)
        XCTAssertTrue(AppPreferences.hasRatedApp(in: defaults))

        var fired: [Int] = []
        for _ in 0..<60 {
            if AppPreferences.recordSuccessfulAction(now: Date(), in: defaults) {
                fired.append(AppPreferences.successfulActionCount(in: defaults))
            }
        }
        XCTAssertEqual(fired, [])
        XCTAssertEqual(AppPreferences.successfulActionCount(in: defaults), 60)
    }

    func testShareMessageBakesStatAndStoreLink() {
        let withStat = AppStoreLinks.shareMessage(statLine: "removed 24 duplicates")
        XCTAssertTrue(withStat.contains("I just removed 24 duplicates"))
        XCTAssertTrue(withStat.contains(AppStoreLinks.appStoreURL.absoluteString))

        let generic = AppStoreLinks.shareMessage(statLine: nil)
        XCTAssertTrue(generic.contains("cleaning up my photo library"))
        XCTAssertFalse(generic.contains("I just"))
    }
}
