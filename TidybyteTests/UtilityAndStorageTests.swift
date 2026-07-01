import XCTest
import SwiftUI
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

    func testBurstBadgeCountUsesGroupCount() {
        let groups: [String: [AssetSummary]] = [
            "burst-1": [],
            "burst-2": []
        ]

        XCTAssertEqual(CleanupHomeViewModel.burstBadgeCount(from: groups), 2)
    }

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
}
