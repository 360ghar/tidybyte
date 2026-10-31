import XCTest
@testable import Tidybyte

/// The swipe card's image-request policy: the size it asks for, and when a
/// resize invalidates the decode already on screen.
///
/// This is the seam for the resize behaviour. Proving it end to end needs a
/// foldable runtime (folding the device mid-session), which is not installed in
/// this environment — only the iOS 27.0 simulator runtime is available — so the
/// rules are covered here as pure values instead.
final class CardImageRequestTests: XCTestCase {

    // MARK: - Request size

    func testRequestPrefersTheDecksPublishedTarget() {
        let size = CardImageRequest.size(
            deckTarget: CGSize(width: 1170, height: 2100),
            frame: CGSize(width: 390, height: 700),
            displayScale: 3
        )
        XCTAssertEqual(size, CGSize(width: 1170, height: 2100), "The deck's target is what the session prefetched, so it wins")
    }

    func testRequestFallsBackToTheCardsOwnFrameBeforeTheDeckMeasures() {
        let size = CardImageRequest.size(
            deckTarget: .zero,
            frame: CGSize(width: 390, height: 700),
            displayScale: 3
        )
        XCTAssertEqual(size, CGSize(width: 1170, height: 2100))
    }

    /// Both inputs can be unmeasured on the first layout pass. A `.zero`
    /// `PHImageManager` target is a degenerate request, so the size is floored.
    func testRequestIsNeverDegenerate() {
        let size = CardImageRequest.size(deckTarget: .zero, frame: .zero, displayScale: 3)
        XCTAssertEqual(size, CGSize(width: CardImageRequest.minimumPixels, height: CardImageRequest.minimumPixels))
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }

    func testRequestFloorsASmallUnmeasuredFrame() {
        // A 10×10pt frame at 3x is 30px — under the floor, so it is lifted.
        let size = CardImageRequest.size(
            deckTarget: .zero,
            frame: CGSize(width: 10, height: 10),
            displayScale: 3
        )
        XCTAssertEqual(size.width, CardImageRequest.minimumPixels)
        XCTAssertEqual(size.height, CardImageRequest.minimumPixels)
    }

    func testRequestLeavesARealTargetAlone() {
        let size = CardImageRequest.size(
            deckTarget: CGSize(width: 1302, height: 1452),
            frame: .zero,
            displayScale: 3
        )
        XCTAssertEqual(size, CGSize(width: 1302, height: 1452), "The floor must not clamp a real card")
    }

    // MARK: - Reload decision

    func testReloadIsSkippedWhileNothingIsOnScreen() {
        XCTAssertFalse(
            CardImageRequest.shouldReload(
                currentTarget: CGSize(width: 1170, height: 2100),
                lastRequestedTarget: .zero,
                hasImage: false
            ),
            "The first load is the .task's job — a resize must not double-load it"
        )
    }

    func testReloadIsSkippedForAnUnmeasuredTarget() {
        XCTAssertFalse(
            CardImageRequest.shouldReload(
                currentTarget: .zero,
                lastRequestedTarget: CGSize(width: 1170, height: 2100),
                hasImage: true
            )
        )
    }

    func testReloadIsSkippedWhenTheTargetIsUnchanged() {
        let target = CGSize(width: 1170, height: 2100)
        XCTAssertFalse(
            CardImageRequest.shouldReload(currentTarget: target, lastRequestedTarget: target, hasImage: true),
            "An ordinary layout pass republishes the same target and must not restart the load"
        )
    }

    /// The deck's rect and the card's rect are one rect reported by two
    /// geometry observers, so they can differ in the last fraction of a point.
    func testReloadIgnoresSubPixelGeometryNoise() {
        XCTAssertFalse(
            CardImageRequest.shouldReload(
                currentTarget: CGSize(width: 1170.0003, height: 2100),
                lastRequestedTarget: CGSize(width: 1170, height: 2100),
                hasImage: true
            )
        )
    }

    func testReloadFiresOnARealTargetChange() {
        XCTAssertTrue(
            CardImageRequest.shouldReload(
                currentTarget: CGSize(width: 1302, height: 1452), // folded, outer display
                lastRequestedTarget: CGSize(width: 1680, height: 2271), // unfolded, inner
                hasImage: true
            ),
            "A fold/unfold changes the decode size, so the visible card must re-request"
        )
    }

    func testReloadFiresOnAOneAxisChange() {
        XCTAssertTrue(
            CardImageRequest.shouldReload(
                currentTarget: CGSize(width: 1170, height: 1400),
                lastRequestedTarget: CGSize(width: 1170, height: 2100),
                hasImage: true
            ),
            "A squat window changes height only, and that is still a stale decode"
        )
    }
}
