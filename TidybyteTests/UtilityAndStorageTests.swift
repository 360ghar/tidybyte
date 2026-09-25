import XCTest
import SwiftUI
import UIKit
@testable import Tidybyte

final class UtilityAndStorageTests: XCTestCase {

    func testSetToggleInsertsThenRemoves() {
        var set: Set<String> = []
        set.toggle("a")
        XCTAssertTrue(set.contains("a"))
        set.toggle("a")
        XCTAssertFalse(set.contains("a"))
    }

    func testSetToggleIsIndependentPerElement() {
        var set: Set<String> = ["a"]
        set.toggle("b")
        XCTAssertEqual(set, ["a", "b"])
        set.toggle("a")
        XCTAssertEqual(set, ["b"])
    }

    func testDeviceUsedCapacityIsNonNegativeWhenAvailableExceedsTotal() {
        // available-for-important-usage can momentarily exceed total capacity.
        let info = DeviceStorageInfo(totalCapacity: 100, availableCapacity: 150)
        XCTAssertEqual(info.usedCapacity, 0)
    }

    func testDeviceUsedCapacityNormalCase() {
        let info = DeviceStorageInfo(totalCapacity: 256_000_000_000, availableCapacity: 56_000_000_000)
        XCTAssertEqual(info.usedCapacity, 200_000_000_000)
    }

    // (burstBadgeCount test removed with the helper itself, E8: it asserted
    // `groups.count == groups.count` — a tautology around an inlined value.)

    @MainActor
    func testOnDeviceMediaExcludesICloudOnly() {
        let vm = StorageDashboardViewModel()
        vm.categories = [StorageCategory(id: "photos", name: "Photos", bytes: 100, count: 1, color: .blue)]
        vm.iCloudOnlySize = 40
        // 100 total library − 40 iCloud-only = 60 locally resident.
        XCTAssertEqual(vm.onDeviceMediaSize, 60)
    }

    @MainActor
    func testAppsAndOtherIsUsedMinusOnDeviceMedia() {
        let vm = StorageDashboardViewModel()
        vm.categories = [StorageCategory(id: "photos", name: "Photos", bytes: 100, count: 1, color: .blue)]
        vm.iCloudOnlySize = 40
        vm.deviceStorage = DeviceStorageInfo(totalCapacity: 1000, availableCapacity: 900) // used = 100
        // used 100 − on-device media 60 = 40 for apps/system/other.
        XCTAssertEqual(vm.appsAndOtherSize, 40)
    }

    @MainActor
    func testAppsAndOtherClampsToZeroWhenMediaExceedsUsed() {
        let vm = StorageDashboardViewModel()
        vm.categories = [StorageCategory(id: "photos", name: "Photos", bytes: 200, count: 1, color: .blue)]
        vm.iCloudOnlySize = 0
        vm.deviceStorage = DeviceStorageInfo(totalCapacity: 100, availableCapacity: 0) // used = 100
        // on-device media (200) > used (100) → clamp to 0 rather than render negative.
        XCTAssertEqual(vm.appsAndOtherSize, 0)
    }

    // MARK: - Thumbnail cache staleness is scoped per asset (PR #2 finding)

    /// The eviction counter used to be global, so editing asset B discarded a
    /// perfectly fresh in-flight load of unrelated asset A — and the next scroll
    /// re-fetched from disk for no reason.
    func testImageCacheStampIsScopedPerAsset() async {
        let cache = ImageCache(countLimit: 10, totalCostLimit: 1_000_000)
        let image = makeTestImage()
        let stampA = await cache.stamp(for: "a")
        let stampB = await cache.stamp(for: "b")

        await cache.removeAllVariants(of: "b")

        let storedA = await cache.setImage(image, for: "a", assetId: "a", ifStamp: stampA)
        XCTAssertTrue(storedA, "an edit of another asset must not invalidate this load")

        let storedB = await cache.setImage(image, for: "b", assetId: "b", ifStamp: stampB)
        XCTAssertFalse(storedB, "this asset's own eviction must refuse the stale store")
    }

    /// A global flush (`removeAll`) invalidates every in-flight load, including
    /// ones whose per-asset version did not move.
    func testImageCacheStampRejectsAfterGlobalFlush() async {
        let cache = ImageCache(countLimit: 10, totalCostLimit: 1_000_000)
        let stamp = await cache.stamp(for: "a")

        await cache.removeAll()

        let stored = await cache.setImage(makeTestImage(), for: "a", assetId: "a", ifStamp: stamp)
        XCTAssertFalse(stored)
    }

    private func makeTestImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}
