import Foundation
@testable import MacOSCleanerCore
import XCTest

/// APFS clone-based deduplication end to end: fold/unfold primitives, the
/// detector's recommendation changes, the auditor's clone-specific gates, and
/// the executor/undo round trip — all against real files on this APFS volume.
final class CloneDedupTests: XCTestCase {
    private func makeTemporaryDirectory(named prefix: String = "CloneDedup") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacOSCleaner-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFile(_ path: String, in root: URL, content: Data, backdate: Bool = true) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try content.write(to: url)
        // Backdate mtime by default: a freshly written file is inside the
        // fold's quiet period and would be skipped as recently modified.
        if backdate {
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: url.path
            )
        }
        return url
    }

    private func identity(of url: URL) throws -> (device: UInt64, inode: UInt64) {
        let captured = try XCTUnwrap(FileArtifactIdentity.capture(at: url))
        return (captured.deviceID, captured.inodeID)
    }

    /// A FileRecord mirroring a real file on disk, with true identity fields.
    private func record(
        id: String, for url: URL, device: UInt64, inode: UInt64, cloudProvider: String? = nil
    ) -> FileRecord {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = attributes?[.modificationDate] as? Date
        return FileRecord(
            id: id, scanSessionID: "scan", source: .local, url: url,
            displayPath: url.path, fileName: url.lastPathComponent,
            fileExtension: url.pathExtension, utiDescription: nil,
            kind: .regularFile, sizeBytes: size,
            createdAt: modified, modifiedAt: modified, lastOpenedAt: nil,
            owner: nil, permissions: nil, isSymlink: false, symlinkTarget: nil,
            isPackage: false, isCloudPlaceholder: false, cloudProvider: cloudProvider,
            finderTags: [], spotlightMetadata: [:], riskFlags: [],
            identity: FileIdentity(
                deviceIdentifier: device, inodeIdentifier: inode,
                resourceIdentifier: nil, sizeBytes: size, modifiedAt: modified
            ),
            capabilities: []
        )
    }

    // MARK: - APFSCloneService.fold

    func testFoldKeepsBothPathsAndFreesBlocks() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let keeper = try makeFile("keeper.bin", in: root, content: Data("identical payload".utf8))
        let duplicate = try makeFile("nested/duplicate.bin", in: root, content: Data("identical payload".utf8))
        let before = try identity(of: duplicate)

        let outcome = APFSCloneService.fold(duplicate: duplicate, keeper: keeper, quietPeriod: 0)

        guard case .folded(let freed) = outcome else {
            return XCTFail("Expected a successful fold, got \(outcome)")
        }
        XCTAssertGreaterThan(freed, 0)
        // The path survives with identical contents, but it is a NEW inode
        // (a clone of the keeper's blocks).
        XCTAssertEqual(try Data(contentsOf: duplicate), Data("identical payload".utf8))
        let after = try identity(of: duplicate)
        XCTAssertNotEqual(after.inode, before.inode, "Fold must replace the duplicate's inode with the keeper's clone")
        // No temp files left behind.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("nested").path)
        XCTAssertTrue(leftovers.allSatisfy { !$0.hasPrefix(APFSCloneService.tempFilePrefix) })
    }

    func testFoldIsolatesCopyOnWriteEdits() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let keeper = try makeFile("keeper.txt", in: root, content: Data("shared bytes".utf8))
        let duplicate = try makeFile("duplicate.txt", in: root, content: Data("shared bytes".utf8))

        guard case .folded = APFSCloneService.fold(duplicate: duplicate, keeper: keeper, quietPeriod: 0) else {
            return XCTFail("Fold should succeed")
        }
        // Writing one copy must never touch the other — the core clone contract.
        try Data("private edit".utf8).write(to: duplicate)
        XCTAssertEqual(try Data(contentsOf: keeper), Data("shared bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: duplicate), Data("private edit".utf8))
    }

    func testFoldPreservesDuplicateMetadata() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let keeper = try makeFile("keeper.txt", in: root, content: Data("same".utf8))
        let duplicate = try makeFile("duplicate.txt", in: root, content: Data("same".utf8))
        let name = "com.sakshammittal.tidybyte.test.xattr"
        XCTAssertEqual(setxattr(duplicate.path, name, "duplicate-value", 15, 0, 0), 0)

        guard case .folded = APFSCloneService.fold(duplicate: duplicate, keeper: keeper, quietPeriod: 0) else {
            return XCTFail("Fold should succeed")
        }
        var buffer = [UInt8](repeating: 0, count: 64)
        let read = getxattr(duplicate.path, name, &buffer, buffer.count, 0, 0)
        XCTAssertEqual(read, 15)
        XCTAssertEqual(String(bytes: buffer.prefix(15), encoding: .utf8), "duplicate-value")
    }

    func testFoldSkipsHardlinkedPairAsAlreadyShared() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let keeper = try makeFile("keeper.txt", in: root, content: Data("one storage".utf8))
        let hardlink = root.appendingPathComponent("hardlink.txt")
        try FileManager.default.linkItem(at: keeper, to: hardlink)

        let outcome = APFSCloneService.fold(duplicate: hardlink, keeper: keeper, quietPeriod: 0)
        XCTAssertEqual(outcome, .alreadyShared)
    }

    func testFoldRejectsChangedContents() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let keeper = try makeFile("keeper.txt", in: root, content: Data("version A".utf8))
        let duplicate = try makeFile("duplicate.txt", in: root, content: Data("version B".utf8))

        let outcome = APFSCloneService.fold(duplicate: duplicate, keeper: keeper, quietPeriod: 0)
        XCTAssertEqual(outcome, .changed("contents differ"))
        XCTAssertEqual(
            try Data(contentsOf: duplicate), Data("version B".utf8),
            "A declined fold must leave the file untouched"
        )
    }

    func testFoldSkipsRecentlyModifiedFiles() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // Fresh files (no backdate) are inside the default 5-minute window.
        let keeper = try makeFile("keeper.txt", in: root, content: Data("fresh".utf8), backdate: false)
        let duplicate = try makeFile("duplicate.txt", in: root, content: Data("fresh".utf8), backdate: false)

        let outcome = APFSCloneService.fold(duplicate: duplicate, keeper: keeper)
        XCTAssertEqual(outcome, .skipped("modified in the last few minutes"))
    }

    // MARK: - APFSCloneService.unfold (undo)

    func testUndoRoundTripRestoresPrivateCopy() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let keeper = try makeFile("keeper.bin", in: root, content: Data("shared data".utf8))
        let duplicate = try makeFile("duplicate.bin", in: root, content: Data("shared data".utf8))
        guard case .folded = APFSCloneService.fold(duplicate: duplicate, keeper: keeper, quietPeriod: 0) else {
            return XCTFail("Fold should succeed")
        }
        let foldedInode = try identity(of: duplicate).inode

        XCTAssertTrue(
            APFSCloneService.unfold(path: duplicate, freeSpaceReserve: 0),
            "Unfold needs free space; the reserve is waived in tests"
        )
        XCTAssertEqual(try Data(contentsOf: duplicate), Data("shared data".utf8))
        let unfoldedInode = try identity(of: duplicate).inode
        XCTAssertNotEqual(unfoldedInode, foldedInode, "Undo must give the file a fresh private inode")
        // And the private copy is truly private again.
        try Data("second edit".utf8).write(to: duplicate)
        XCTAssertEqual(try Data(contentsOf: keeper), Data("shared data".utf8))
    }

    func testUnfoldRefusesIdentityMismatch() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let keeper = try makeFile("keeper.txt", in: root, content: Data("same".utf8))
        let duplicate = try makeFile("duplicate.txt", in: root, content: Data("same".utf8))
        guard case .folded = APFSCloneService.fold(duplicate: duplicate, keeper: keeper, quietPeriod: 0) else {
            return XCTFail("Fold should succeed")
        }
        let actual = try identity(of: duplicate)
        // Wrong expected identity (e.g. the user replaced the file since the
        // fold) must fail closed and leave the file alone.
        XCTAssertFalse(APFSCloneService.unfold(
            path: duplicate,
            expectedDevice: actual.device,
            expectedInode: actual.inode + 999,
            freeSpaceReserve: 0
        ))
        XCTAssertEqual(try Data(contentsOf: duplicate), Data("same".utf8))
    }

    // MARK: - DuplicateDetector

    func testDetectorIgnoresHardlinkTwinsAndStillFindsRealDuplicates() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let content = Data("real duplicate payload".utf8)
        let first = try makeFile("a/original.txt", in: root, content: content)
        let twin = root.appendingPathComponent("b/twin.txt")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("b"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: first, to: twin)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: twin.path
        )
        let copy = try makeFile("c/copy.txt", in: root, content: content)

        func captured(_ url: URL) throws -> FileRecord {
            let captured = try XCTUnwrap(FileArtifactIdentity.capture(at: url))
            return record(id: url.path, for: url, device: captured.deviceID, inode: captured.inodeID)
        }
        let detector = DuplicateDetector()
        let analysis = try await detector.analyze(
            files: [try captured(first), try captured(twin), try captured(copy)],
            sessionID: "s",
            strategy: .moveToTrash
        )
        // The hardlink twin IS the same storage as `first`: only `copy` can
        // pair with it, so exactly one group of two — not three.
        let duplicateFindings = analysis.findings.filter { $0.category == .duplicate }
        XCTAssertEqual(duplicateFindings.count, 1)
        XCTAssertEqual(duplicateFindings[0].targetFileIDs.count, 2)
    }

    func testDetectorRecommendsCloneFoldByDefault() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let content = Data("identical payload".utf8)
        // Stagger mtimes: the newest copy always becomes the keeper.
        let duplicate = try makeFile("duplicate.txt", in: root, content: content, backdate: false)
        try await Task.sleep(for: .milliseconds(50))
        let keeper = try makeFile("original.txt", in: root, content: content, backdate: false)

        let analysis = try await analyzeInMemory(files: [keeper, duplicate], strategy: .apfsClone)
        let recommendation = try XCTUnwrap(analysis.recommendations.first)
        XCTAssertEqual(recommendation.actionType, .cloneDeduplicate)
        XCTAssertEqual(recommendation.targetFileIDs, [duplicate.path])
        let keeperURL = try XCTUnwrap(recommendation.destination)
        XCTAssertEqual(keeperURL.path, keeper.path)
        XCTAssertEqual(analysis.findings.first?.evidence["kept_file"], keeper.path)
    }

    func testDetectorTrashStrategyPreservesClassicBehavior() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let content = Data("identical payload".utf8)
        let duplicate = try makeFile("duplicate.txt", in: root, content: content, backdate: false)
        try await Task.sleep(for: .milliseconds(50))
        let keeper = try makeFile("original.txt", in: root, content: content, backdate: false)

        let analysis = try await analyzeInMemory(files: [keeper, duplicate], strategy: .moveToTrash)
        XCTAssertEqual(analysis.recommendations.count, 1)
        XCTAssertEqual(analysis.recommendations[0].actionType, .moveToTrash)
        XCTAssertNil(analysis.recommendations[0].destination)
    }

    func testDetectorSplitsCloudMemberIntoSeparateTrashRecommendation() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let content = Data("identical payload".utf8)
        // The cloud copy is NEWEST — but a cloud-synced copy must never be
        // the keeper: folding a local file onto it would break the sync.
        let oldest = try makeFile("original.txt", in: root, content: content)
        try await Task.sleep(for: .milliseconds(50))
        let newestLocal = try makeFile("local-copy.txt", in: root, content: content, backdate: false)
        try await Task.sleep(for: .milliseconds(50))
        let cloudCopy = try makeFile("cloud-copy.txt", in: root, content: content, backdate: false)

        func capturedRecord(_ url: URL) throws -> FileRecord {
            let captured = try XCTUnwrap(FileArtifactIdentity.capture(at: url))
            return record(id: url.path, for: url, device: captured.deviceID, inode: captured.inodeID)
        }
        var cloudRecord = try capturedRecord(cloudCopy)
        cloudRecord.cloudProvider = "Dropbox"
        let oldestRecord = try capturedRecord(oldest)
        let newestLocalRecord = try capturedRecord(newestLocal)

        let analysis = try await DuplicateDetector().analyze(
            files: [oldestRecord, newestLocalRecord, cloudRecord], sessionID: "s", strategy: .apfsClone
        )
        // The newest LOCAL copy keeps; the other local copy folds onto it;
        // the cloud-synced copy is trash-only (sync engines must never see
        // an inode swap).
        XCTAssertEqual(analysis.recommendations.count, 2)
        XCTAssertEqual(analysis.recommendations.first?.actionType, .cloneDeduplicate)
        XCTAssertEqual(analysis.recommendations.first?.targetFileIDs, [oldest.path])
        XCTAssertEqual(analysis.recommendations.first?.destination?.path, newestLocal.path)
        XCTAssertEqual(analysis.recommendations.last?.actionType, .moveToTrash)
        XCTAssertEqual(analysis.recommendations.last?.targetFileIDs, [cloudCopy.path])
    }

    func testDetectorReusesPersistedHashCache() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let content = Data("cache me".utf8)
        let first = try makeFile("one.txt", in: root, content: content)
        let second = try makeFile("two.txt", in: root, content: content)

        let store = try SQLiteStore.inMemory()
        let detector = DuplicateDetector(hashCache: store)
        _ = try await detector.analyze(files: recordsFor([first, second]), sessionID: "s1", strategy: .moveToTrash)

        let modified = try XCTUnwrap(
            (try FileManager.default.attributesOfItem(atPath: first.path)[.modificationDate]) as? Date
        )
        let size = try XCTUnwrap(
            (try FileManager.default.attributesOfItem(atPath: first.path)[.size] as? NSNumber)?.int64Value
        )
        let cached = try await store.cachedFullHash(forPath: first.path, sizeBytes: size, modifiedAt: modified)
        XCTAssertNotNil(cached, "Full hash must be persisted for the next scan")

        // A fresh detector sharing the store resolves the cached hash without
        // re-reading and still finds the same group.
        let secondDetector = DuplicateDetector(hashCache: store)
        let analysis = try await secondDetector.analyze(
            files: recordsFor([first, second]), sessionID: "s2", strategy: .moveToTrash
        )
        XCTAssertEqual(analysis.findings.filter { $0.category == .duplicate }.count, 1)
    }

    // MARK: Helpers

    private func analyzeInMemory(files: [URL], strategy: DuplicateStrategy) async throws -> DuplicateAnalysis {
        var records: [FileRecord] = []
        for url in files {
            let captured = try XCTUnwrap(FileArtifactIdentity.capture(at: url))
            records.append(record(id: url.path, for: url, device: captured.deviceID, inode: captured.inodeID))
        }
        return try await DuplicateDetector().analyze(files: records, sessionID: "s", strategy: strategy)
    }

    private func recordsFor(_ urls: [URL]) throws -> [FileRecord] {
        var records: [FileRecord] = []
        for url in urls {
            let captured = try XCTUnwrap(FileArtifactIdentity.capture(at: url))
            records.append(record(id: url.path, for: url, device: captured.deviceID, inode: captured.inodeID))
        }
        return records
    }
}
