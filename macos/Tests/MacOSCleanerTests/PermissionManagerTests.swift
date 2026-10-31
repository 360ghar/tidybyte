import Foundation
@testable import MacOSCleanerCore
import XCTest

final class PermissionManagerTests: XCTestCase {
    func testPermissionManagerReturnsRootsForSelectedFolders() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = PermissionManager()
        let roots = try await manager.roots(for: .selectedFolders, selectedFolders: [root])

        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots.first?.path, root.path)
    }

    func testPermissionManagerReturnsHomeForHomeFolderMode() async throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let manager = PermissionManager(homeDirectoryOverride: home)
        let roots = try await manager.roots(for: .homeFolder, selectedFolders: [])

        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots.first, home.standardizedFileURL)
    }

    func testPermissionManagerReturnsEmptyForDeveloperWithNoSelection() async throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let manager = PermissionManager(homeDirectoryOverride: home)
        let roots = try await manager.roots(for: .developerCleanup, selectedFolders: [])

        // A fresh temp home has no developer roots, so the result is empty.
        XCTAssertTrue(roots.isEmpty)
    }

    func testPermissionManagerPermissionsSnapshot() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = PermissionManager()
        let snapshot = await manager.permissionsSnapshot(for: [root], mode: .selectedFolders)

        // Should return a non-empty snapshot string
        XCTAssertFalse(snapshot.isEmpty)
    }

    func testPermissionManagerMountedVolumes() async throws {
        let manager = PermissionManager()
        let volumes = await manager.mountedVolumes()

        // Should return at least the boot volume
        XCTAssertFalse(volumes.isEmpty)
        XCTAssertTrue(volumes.contains { $0.isInternal })
    }

    func makeTemporaryDirectory() throws -> URL {
        try TestFixtures.makeTemporaryDirectory()
    }
}
