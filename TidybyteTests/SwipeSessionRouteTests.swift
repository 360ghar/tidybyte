import XCTest
@testable import Tidybyte

/// Identity of a swipe session's navigation route.
///
/// Deliberately thin: the swipe-left / undo / accumulate behaviour these tests
/// used to cover — including the pending byte totals and the undo stack's
/// contents — lives in `SwipeSessionDeletionTests`, which asserts that state
/// plus the record writes this file never checked.
final class SwipeSessionRouteTests: XCTestCase {
    func testSameFilterCreatesDistinctRoutes() {
        let first = SwipeSessionRoute(filter: .allMedia)
        let second = SwipeSessionRoute(filter: .allMedia)

        // `navigationDestination(item:)` pushes a new session only when the item
        // differs by identity: two sessions over the same filter must not collide
        // into one, or re-opening a session would silently do nothing.
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.filter, second.filter)
    }
}
