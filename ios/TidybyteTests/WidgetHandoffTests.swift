import XCTest
@testable import Tidybyte

/// Tests for the widget → app handoff (App Group route queue) and for
/// `WidgetSnapshot`'s forward/backward compatibility, which is the one change
/// that could silently blank the widget for existing users.
final class WidgetHandoffTests: XCTestCase {

    private func snapshot(lifetimeFreedBytes: Int64?, lifetimeItemCount: Int?) -> WidgetSnapshot {
        WidgetSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1_000),
            usedBytes: 10,
            totalBytes: 20,
            screenshotCount: 1,
            screenshotBytes: 2,
            largeFileCount: 3,
            largeFileBytes: 4,
            reclaimableBytes: 5,
            lifetimeFreedBytes: lifetimeFreedBytes,
            lifetimeItemCount: lifetimeItemCount
        )
    }

    // MARK: - Route handoff

    func testPendingRouteRoundTripsForEveryCase() {
        for route in [WidgetRoute.swipe, .screenshots, .activity] {
            AppGroupStore.savePendingRoute(route)
            XCTAssertEqual(AppGroupStore.consumePendingRoute(), route)
        }
        AppGroupStore.consumePendingRoute()
    }

    func testConsumeClearsTheRouteSoItCannotReplay() {
        AppGroupStore.savePendingRoute(.activity)
        XCTAssertEqual(AppGroupStore.consumePendingRoute(), .activity)
        XCTAssertNil(AppGroupStore.consumePendingRoute(), "a widget tap must not re-open the app forever")
    }

    func testConsumeReturnsNilWhenNothingIsQueued() {
        AppGroupStore.consumePendingRoute()
        XCTAssertNil(AppGroupStore.consumePendingRoute())
    }

    // MARK: - Snapshot compatibility

    /// The critical regression: a snapshot written by v1.0.x has no lifetime
    /// keys. Decoding must still succeed (the fields are optional), otherwise
    /// the widget renders its placeholder for every existing user until the app
    /// happens to run again.
    func testLegacySnapshotWithoutLifetimeKeysStillDecodes() throws {
        let legacyJSON = """
        {
          "capturedAt": 1000,
          "usedBytes": 10,
          "totalBytes": 20,
          "screenshotCount": 1,
          "screenshotBytes": 2,
          "largeFileCount": 3,
          "largeFileBytes": 4,
          "reclaimableBytes": 5
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: legacyJSON)

        XCTAssertEqual(decoded.reclaimableBytes, 5)
        XCTAssertNil(decoded.lifetimeFreedBytes)
        XCTAssertNil(decoded.lifetimeItemCount)
    }

    func testSnapshotRoundTripsIncludingLifetimeTotals() throws {
        let original = snapshot(lifetimeFreedBytes: 7_500, lifetimeItemCount: 12)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.lifetimeFreedBytes, 7_500)
        XCTAssertEqual(decoded.lifetimeItemCount, 12)
        XCTAssertEqual(decoded.reclaimableBytes, original.reclaimableBytes)
    }

    func testSnapshotWithNilLifetimeTotalsEncodesAndDecodes() throws {
        let original = snapshot(lifetimeFreedBytes: nil, lifetimeItemCount: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        XCTAssertNil(decoded.lifetimeFreedBytes)
        XCTAssertNil(decoded.lifetimeItemCount)
    }

    /// `AppGroupStore.save` / `loadSnapshot` must be a faithful round trip — the
    /// widget reads exactly what the app wrote. Restores the prior payload so a
    /// test run can't leave a fabricated snapshot behind for the real widget.
    func testAppGroupStoreRoundTripsTheFullSnapshot() {
        let previous = AppGroupStore.loadSnapshot()
        defer {
            if let previous {
                AppGroupStore.save(previous)
            }
        }

        let written = snapshot(lifetimeFreedBytes: 4_300, lifetimeItemCount: 9)
        AppGroupStore.save(written)
        let read = AppGroupStore.loadSnapshot()

        XCTAssertEqual(read?.lifetimeFreedBytes, 4_300)
        XCTAssertEqual(read?.lifetimeItemCount, 9)
        XCTAssertEqual(read?.screenshotCount, written.screenshotCount)
    }

    // MARK: - Deep links

    func testActivityDeepLinkParses() {
        XCTAssertEqual(DeepLink.from(url: URL(string: "tidybyte://activity")!), .activity)
    }

    /// A widget button tap must land on the same destination the equivalent URL
    /// would, so the two entry points can't drift apart.
    func testWidgetRoutesMapToTheSameDestinationsAsDeepLinks() {
        XCTAssertEqual(DeepLink.from(url: URL(string: "tidybyte://swipe")!), .swipe)
        XCTAssertEqual(DeepLink.from(url: URL(string: "tidybyte://cleanup/screenshots")!), .cleanupTool(.screenshots))
        XCTAssertEqual(DeepLink.from(url: URL(string: "tidybyte://activity")!), .activity)
    }

    // MARK: - Navigation

    @MainActor
    func testShowActivitySwitchesToTheStorageTabAndPushesTheRoute() {
        let navigation = AppNavigation()
        navigation.selectedTab = .swipe

        navigation.showActivity()

        XCTAssertEqual(navigation.selectedTab, .storage)
        XCTAssertEqual(navigation.storagePath, [.activity])
    }

    @MainActor
    func testStorageDeepLinkClearsAPushedActivityScreen() {
        let navigation = AppNavigation()
        navigation.showActivity()

        navigation.handle(.storage)

        XCTAssertEqual(navigation.selectedTab, .storage)
        XCTAssertTrue(navigation.storagePath.isEmpty, "a bare storage link returns to the dashboard root")
    }

    @MainActor
    func testActivityDeepLinkRoutesThroughTheStorageStack() {
        let navigation = AppNavigation()
        navigation.handle(.activity)

        XCTAssertEqual(navigation.selectedTab, .storage)
        XCTAssertEqual(navigation.storagePath, [.activity])
    }
}
