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

    // MARK: - Resource cache

    func testResourceCacheReusesAnUnchangedAsset() {
        let cache = ResourceCache()
        let date = Date(timeIntervalSince1970: 1_000)
        var reads = 0
        for _ in 0..<2 {
            _ = cache.resources(id: "a", modifiedAt: date, stamp: cache.stamp()) { reads += 1; return facts() }
        }
        XCTAssertEqual(reads, 1)
    }

    /// An edit moves the asset's modification date: read it again.
    func testResourceCacheRereadsAnEditedAsset() {
        let cache = ResourceCache()
        _ = cache.resources(id: "a", modifiedAt: Date(timeIntervalSince1970: 1_000), stamp: cache.stamp()) { facts(size: 1) }
        let edited = cache.resources(id: "a", modifiedAt: Date(timeIntervalSince1970: 2_000), stamp: cache.stamp()) { facts(size: 2) }
        XCTAssertEqual(edited.fileSize, 2)
    }

    /// iCloud downloads don't always produce a library change: an old read
    /// is read again even if nothing evicted it.
    func testResourceCacheRereadsAfterMaxAge() {
        let clock = TestClock()
        let cache = ResourceCache(now: { clock.now })
        _ = cache.resources(id: "a", modifiedAt: nil, stamp: cache.stamp()) { facts() }
        var reads = 0
        clock.now += ResourceCache.maxAge - 1
        _ = cache.resources(id: "a", modifiedAt: nil, stamp: cache.stamp()) { reads += 1; return facts() }
        XCTAssertEqual(reads, 0)
        clock.now += 2
        _ = cache.resources(id: "a", modifiedAt: nil, stamp: cache.stamp()) { reads += 1; return facts() }
        XCTAssertEqual(reads, 1)
    }

    func testResourceCacheRereadsRemovedAssetsOnly() {
        let cache = ResourceCache()
        func read(_ ids: [String]) -> [String] {
            let stamp = cache.stamp()
            var reads: [String] = []
            for id in ids {
                _ = cache.resources(id: id, modifiedAt: nil, stamp: stamp) { reads.append(id); return facts() }
            }
            return reads
        }
        XCTAssertEqual(read(["a", "b"]), ["a", "b"])
        cache.remove(["a"])
        XCTAssertEqual(read(["a", "b"]), ["a"])
        cache.removeAll()
        XCTAssertEqual(read(["a", "b"]), ["a", "b"])
        XCTAssertEqual(read(["a", "b"]), [])
    }

    /// A fetch made before a change holds the changed asset as it was, even if
    /// its build only starts after the change (queued behind another build):
    /// nothing it reads for that asset is kept.
    func testResourceCacheKeepsNothingAFetchReadForAnAssetRemovedAfterIt() {
        let cache = ResourceCache()
        let stamp = cache.stamp()
        _ = cache.resources(id: "a", modifiedAt: nil, stamp: stamp) { facts() }
        cache.remove(["b"])
        _ = cache.resources(id: "b", modifiedAt: nil, stamp: stamp) { facts() }
        _ = cache.resources(id: "c", modifiedAt: nil, stamp: stamp) { facts() }

        var reads: [String] = []
        let next = cache.stamp()
        for id in ["a", "b", "c"] {
            _ = cache.resources(id: id, modifiedAt: nil, stamp: next) { reads.append(id); return facts() }
        }
        XCTAssertEqual(reads, ["b"], "only the asset removed after the fetch is read again")
    }

    func testResourceCacheKeepsNothingAFetchReadAfterAClear() {
        let cache = ResourceCache()
        let stamp = cache.stamp()
        cache.removeAll()
        _ = cache.resources(id: "a", modifiedAt: nil, stamp: stamp) { facts() }
        var reads = 0
        _ = cache.resources(id: "a", modifiedAt: nil, stamp: cache.stamp()) { reads += 1; return facts() }
        XCTAssertEqual(reads, 1)
    }

    /// Duplicate scans and exports drop one asset at a time, thousands of
    /// times: that must never wipe the rest of the cache.
    func testResourceCacheKeepsOtherAssetsThroughManyRemovals() {
        let cache = ResourceCache()
        _ = cache.resources(id: "a", modifiedAt: nil, stamp: cache.stamp()) { facts() }
        for index in 0..<20_000 { cache.remove(["removed-\(index)"]) }
        var reads = 0
        _ = cache.resources(id: "a", modifiedAt: nil, stamp: cache.stamp()) { reads += 1; return facts() }
        XCTAssertEqual(reads, 0)
    }

    /// Pruning removals (on later removals and on releases) must keep the
    /// ones a still-open fetch needs: its stale read of "a" is not kept.
    func testResourceCachePruningKeepsRemovalsAnOpenFetchNeeds() {
        let cache = ResourceCache()
        let open = cache.stamp()
        cache.remove(["a"])
        for index in 0..<100 { cache.remove(["other-\(index)"]) }
        cache.release(cache.stamp())
        _ = cache.resources(id: "a", modifiedAt: nil, stamp: open) { facts() }
        cache.release(open)

        var reads = 0
        _ = cache.resources(id: "a", modifiedAt: nil, stamp: cache.stamp()) { reads += 1; return facts() }
        XCTAssertEqual(reads, 1)
    }

    private final class TestClock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 0)
    }

    private func facts(size: Int64 = 1_000) -> ResourceFacts {
        ResourceFacts(fileSize: size, filename: nil, isLocallyAvailable: true, hasScreenRecordingFilename: false)
    }

    private func makeTestImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}
