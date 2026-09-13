import XCTest
@testable import Tidybyte

final class ZoomStateTests: XCTestCase {
    private let frame = CGSize(width: 390, height: 700)

    // MARK: - clampPan

    func testClampPanIsZeroWhenNotZoomed() {
        let pan = ZoomState.clampPan(
            CGSize(width: 100, height: -100),
            scale: 1.0,
            frame: frame
        )
        XCTAssertEqual(pan, .zero)
    }

    func testClampPanBoundsPanToHalfOverflow() {
        // At 2x, each axis overflows by its full size; the limit is half of that.
        let pan = ZoomState.clampPan(
            CGSize(width: 10_000, height: -10_000),
            scale: 2.0,
            frame: frame
        )
        XCTAssertEqual(pan.width, frame.width / 2, accuracy: 0.001)
        XCTAssertEqual(pan.height, -frame.height / 2, accuracy: 0.001)
    }

    func testClampPanKeepsInBoundsPanUntouched() {
        let original = CGSize(width: 42, height: -17)
        let pan = ZoomState.clampPan(original, scale: 2.5, frame: frame)
        XCTAssertEqual(pan, original)
    }

    // MARK: - setScale

    func testSetScaleClampsToMax() {
        var state = ZoomState()
        state.setScale(50, frame: frame)
        XCTAssertEqual(state.scale, ZoomState.maxScale)
    }

    func testSetScaleClampsToOneMinimum() {
        var state = ZoomState()
        state.setScale(0.2, frame: frame)
        XCTAssertEqual(state.scale, 1.0)
        XCTAssertEqual(state.offset, .zero)
    }

    func testSetScaleReClampsExistingPanWhenZoomingOut() {
        var state = ZoomState()
        state.setScale(5.0, frame: frame)
        state.setPan(base: .zero, translation: CGSize(width: frame.width * 2, height: 0), frame: frame)
        XCTAssertEqual(state.offset.width, frame.width * 2, accuracy: 0.001)

        // Zooming out must pull pan back inside the new, smaller bounds.
        state.setScale(1.5, frame: frame)
        XCTAssertEqual(state.offset.width, frame.width * 0.25, accuracy: 0.001)
    }

    // MARK: - setPan

    func testSetPanAddsTranslationToBaseAndClamps() {
        var state = ZoomState()
        state.setScale(2.0, frame: frame)
        state.setPan(base: CGSize(width: 100, height: 50), translation: CGSize(width: 5_000, height: -10), frame: frame)
        XCTAssertEqual(state.offset.width, frame.width / 2, accuracy: 0.001)
        XCTAssertEqual(state.offset.height, 40, accuracy: 0.001)
    }

    // MARK: - toggle

    func testToggleZoomsInOnFirstToggle() {
        var state = ZoomState()
        state.toggle(frame: frame)
        XCTAssertEqual(state.scale, ZoomState.doubleTapScale)
        XCTAssertTrue(state.isZoomed)
    }

    func testToggleResetsOnSecondToggle() {
        var state = ZoomState()
        state.toggle(frame: frame)
        state.toggle(frame: frame)
        XCTAssertEqual(state.scale, 1.0)
        XCTAssertEqual(state.offset, .zero)
        XCTAssertFalse(state.isZoomed)
    }

    // MARK: - endPinch

    func testEndPinchSnapsBackBelowLatchThreshold() {
        var state = ZoomState()
        state.setScale(1.03, frame: frame)
        state.endPinch()
        XCTAssertEqual(state.scale, 1.0)
        XCTAssertFalse(state.isZoomed)
    }

    func testEndPinchLatchesAboveThreshold() {
        var state = ZoomState()
        state.setScale(1.5, frame: frame)
        state.endPinch()
        XCTAssertEqual(state.scale, 1.5)
        XCTAssertTrue(state.isZoomed)
    }

    // MARK: - reset

    func testResetClearsScaleAndOffset() {
        var state = ZoomState()
        state.setScale(3.0, frame: frame)
        state.setPan(base: .zero, translation: CGSize(width: 120, height: 80), frame: frame)
        state.reset()
        XCTAssertEqual(state, ZoomState())
    }

    // MARK: - Boundaries and content-aware clamping

    func testEndPinchAtExactThresholdLatches() {
        var state = ZoomState()
        state.setScale(1.05, frame: frame)
        state.endPinch()
        XCTAssertEqual(state.scale, 1.05, accuracy: 0.0001)
        XCTAssertTrue(state.isZoomed)
    }

    func testEndPinchSnapBackClearsOffset() {
        var state = ZoomState()
        state.setScale(1.03, frame: frame)
        state.setPan(base: .zero, translation: CGSize(width: 100, height: 100), frame: frame)
        // Limits at 1.03x: (390x0.03/2, 700x0.03/2) = (5.85, 10.5).
        XCTAssertEqual(state.offset.width, 5.85, accuracy: 0.001)
        XCTAssertEqual(state.offset.height, 10.5, accuracy: 0.001)
        state.endPinch()
        XCTAssertEqual(state.scale, 1.0)
        XCTAssertEqual(state.offset, .zero)
    }

    func testSetPanAtUnityScaleZeroesOffset() {
        var state = ZoomState()
        state.setPan(base: CGSize(width: 50, height: 50), translation: CGSize(width: 50, height: -20), frame: frame)
        XCTAssertEqual(state.offset, .zero)
    }

    func testToggleDeadZoneBoundary() {
        var lo = ZoomState()
        lo.setScale(1.001, frame: frame)
        XCTAssertFalse(lo.isZoomed)
        lo.toggle(frame: frame)
        XCTAssertEqual(lo.scale, ZoomState.doubleTapScale)
        var hi = ZoomState()
        hi.setScale(1.002, frame: frame)
        XCTAssertTrue(hi.isZoomed)
        hi.toggle(frame: frame)
        XCTAssertEqual(hi.scale, 1.0)
    }

    func testSetScaleMaxBoundary() {
        var a = ZoomState()
        a.setScale(5.0, frame: frame)
        XCTAssertEqual(a.scale, 5.0)
        var b = ZoomState()
        b.setScale(5.0001, frame: frame)
        XCTAssertEqual(b.scale, ZoomState.maxScale)
    }

    func testClampPanWideContentReachesEdges() {
        // Rendered 800x600 content in a 370x600 frame at 2.5x:
        // limits ((800x2.5-370)/2, (600x2.5-600)/2) = (815, 450).
        let card = CGSize(width: 370, height: 600)
        let content = CGSize(width: 800, height: 600)
        let pan = ZoomState.clampPan(CGSize(width: 10_000, height: 10_000), scale: 2.5, frame: card, contentSize: content)
        XCTAssertEqual(pan.width, 815, accuracy: 0.001)
        XCTAssertEqual(pan.height, 450, accuracy: 0.001)
    }

    func testClampPanTallContent() {
        // Rendered 370x804 content in a 370x600 frame at 2.5x:
        // limits ((370x2.5-370)/2, (804x2.5-600)/2) = (277.5, 705).
        let card = CGSize(width: 370, height: 600)
        let content = CGSize(width: 370, height: 804)
        let pan = ZoomState.clampPan(CGSize(width: 10_000, height: 10_000), scale: 2.5, frame: card, contentSize: content)
        XCTAssertEqual(pan.width, 277.5, accuracy: 0.001)
        XCTAssertEqual(pan.height, 705, accuracy: 0.001)
    }

    func testClampPanDefaultsToFrame() {
        let pan = ZoomState.clampPan(CGSize(width: 10_000, height: -10_000), scale: 2.0, frame: frame)
        XCTAssertEqual(pan.width, frame.width / 2, accuracy: 0.001)
        XCTAssertEqual(pan.height, -frame.height / 2, accuracy: 0.001)
    }
}
