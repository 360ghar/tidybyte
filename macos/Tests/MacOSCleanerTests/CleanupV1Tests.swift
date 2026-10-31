import Foundation
import XCTest

@testable import MacOSCleanerAppKit
@testable import MacOSCleanerCore

final class CleanupV1Tests: XCTestCase {
    private func fixture() throws -> URL {
        try TestFixtures.makeTemporaryDirectory(named: "CleanupV1-" + UUID().uuidString)
    }
    private func item(_ name: String, root: URL, content: String = "test document") throws -> ReviewItem {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        return try XCTUnwrap(ReviewInventory.record(url, root: root))
    }

    func testRecursiveInventoryExcludesHiddenPackagesAndSystemPaths() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try item("nested/note.txt", root: root)
        _ = try item(".hidden/secret.txt", root: root)
        _ = try item("Hidden.app/nested.txt", root: root)
        _ = try item("Photos.photoslibrary/nested.txt", root: root)
        let store = try SQLiteStore.inMemory()
        var scope = ReviewScope()
        scope.roots = [root]
        let items = try await ReviewInventory(access: FolderAccess(store: store)).scan(scope) { _ in }
        XCTAssertEqual(items.map(\.name), ["note.txt"])
        for path in [
            "/System/a.jpg", "/Library/a.jpg", "/Applications/App.app/a.jpg",
            ReviewSafety.userHome.appendingPathComponent("Library/a.jpg").path
        ] {
            XCTAssertFalse(ReviewSafety.isAllowed(URL(fileURLWithPath: path)))
        }
    }

    func testSymlinkTrashOnlyMovesTheLink() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try item("original.txt", root: root)
        let link = root.appendingPathComponent("shortcut")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: try XCTUnwrap(original.url))
        let record = try XCTUnwrap(ReviewInventory.record(link, root: root))
        XCTAssertTrue(record.isLink)
        XCTAssertFalse(record.canAnalyze)
        let trash = root.appendingPathComponent("FixtureTrash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: false)
        let store = try SQLiteStore.inMemory()
        let executor = ReviewExecutor(
            store: store, access: FolderAccess(store: store), photos: PhotoLibraryService(),
            trash: FixtureTrash(folder: trash))
        let event = await executor.apply(
            ReviewDecision(item: record, choice: .trash), tool: .swipe, operationID: "link")
        XCTAssertEqual(event.state, .complete)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(original.url).path))
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: trash.appendingPathComponent("shortcut").path),
            original.url?.path)
    }

    func testChangedFileIsRejectedBeforeTrash() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try item("note.txt", root: root)
        try Data("replacement contents".utf8).write(to: try XCTUnwrap(record.url))
        let store = try SQLiteStore.inMemory()
        let executor = ReviewExecutor(
            store: store, access: FolderAccess(store: store), photos: PhotoLibraryService(),
            trash: FixtureTrash(folder: root))
        let event = await executor.apply(
            ReviewDecision(item: record, choice: .trash), tool: .swipe, operationID: "changed")
        XCTAssertEqual(event.state, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(record.url).path))
        XCTAssertEqual(event.savings, 0)
    }

    func testSymlinkAncestorCannotEscapeApprovedScope() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = try fixture()
        defer { try? FileManager.default.removeItem(at: outside) }
        _ = try item("note.txt", root: outside)
        let alias = root.appendingPathComponent("redirect")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: outside)
        let record = try XCTUnwrap(ReviewInventory.record(alias.appendingPathComponent("note.txt"), root: root))
        XCTAssertThrowsError(try ReviewSafety.verify(record))
    }

    func testReviewIdentitySurvivesRenameAndChangesWithContent() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try item("first.txt", root: root)
        let renamed = root.appendingPathComponent("second.txt")
        try FileManager.default.moveItem(at: try XCTUnwrap(original.url), to: renamed)
        let same = try XCTUnwrap(ReviewInventory.record(renamed, root: root))
        XCTAssertEqual(original.id, same.id)
        XCTAssertEqual(original.reviewKey, same.reviewKey)
        try Data("different content with new length".utf8).write(to: renamed)
        let changed = try XCTUnwrap(ReviewInventory.record(renamed, root: root))
        XCTAssertNotEqual(original.reviewKey, changed.reviewKey)
    }

    func testPreciseIdentityAndDraftPersistAcrossDatabaseReopen() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try item("note.txt", root: root)
        let url = root.appendingPathComponent("review.sqlite")
        let store = try SQLiteStore(databaseURL: url)
        var draft = ReviewSession(scopeID: "scope", items: [record])
        draft.decisions = [ReviewDecision(item: record, choice: .skip)]
        try await store.saveCleanupState(Optional(draft), key: "draft")
        await store.close()
        let reopened = try SQLiteStore(databaseURL: url)
        let loaded = try await reopened.loadCleanupState(ReviewSession?.self, key: "draft")
        let restored = try XCTUnwrap(loaded.flatMap { $0 })
        XCTAssertEqual(restored.items.first?.identity, record.identity)
        try ReviewSafety.verify(try XCTUnwrap(restored.items.first))
        XCTAssertNil(restored.current)
    }

    func testTimeGroupsDoNotChainBeyondTheWindow() {
        let items = [0.0, 4, 8].enumerated().map { index, offset in
            var value = ReviewItem(
                id: String(index), source: .file(URL(fileURLWithPath: "/tmp/\(index).jpg")),
                name: "\(index).jpg", kind: .image, bytes: 10)
            value.createdAt = Date(timeIntervalSince1970: 100 + offset)
            return value
        }
        let groups = MediaAnalysisService.timeGroups(items, seconds: 5)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.memberIDs.count, 2)
    }

    func testOverlappingGroupsAlwaysRetainAMember() {
        let groups = [
            AnalysisGroup(tool: .duplicates, memberIDs: ["a", "b"], bestID: "a", explanation: ""),
            AnalysisGroup(tool: .similar, memberIDs: ["b", "c"], bestID: "c", explanation: "")
        ]
        let selection = MediaAnalysisService.safeSelection(["a", "b", "c"], groups: groups)
        for group in groups { XCTAssertFalse(group.memberIDs.allSatisfy(selection.contains)) }
    }

    func testSuccessfulTrashIsIdempotentAndRestorable() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try item("note.txt", root: root)
        let trash = root.appendingPathComponent("FixtureTrash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: false)
        let store = try SQLiteStore.inMemory()
        let executor = ReviewExecutor(
            store: store, access: FolderAccess(store: store), photos: PhotoLibraryService(),
            trash: FixtureTrash(folder: trash))
        let decision = ReviewDecision(item: record, choice: .trash)
        let first = await executor.apply(decision, tool: .swipe, operationID: "once")
        let second = await executor.apply(decision, tool: .swipe, operationID: "once")
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.state, .complete)
        try await executor.restore(first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(record.url).path))
        let events = try await store.cleanupActivity()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.savings, 0)
        XCTAssertEqual(events.first?.restored, true)
        XCTAssertNotNil(events.first?.restoreStartedAt)
        do {
            try await executor.restore(first)
            XCTFail("A stale event must not restore an already restored item")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(record.url).path))
        }
    }

    func testConcurrentRetriesDoNotOverwriteSuccessfulJournal() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try item("note.txt", root: root)
        let trash = root.appendingPathComponent("FixtureTrash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: false)
        let store = try SQLiteStore.inMemory()
        let executor = ReviewExecutor(
            store: store, access: FolderAccess(store: store), photos: PhotoLibraryService(),
            trash: FixtureTrash(folder: trash))
        let decision = ReviewDecision(item: record, choice: .trash)
        await withTaskGroup(of: ActivityEvent.self) { group in
            for _ in 0..<10 {
                group.addTask { await executor.apply(decision, tool: .swipe, operationID: "concurrent") }
            }
            for await _ in group {}
        }
        let event = try await store.cleanupActivity(id: "concurrent")
        XCTAssertEqual(event?.state, .complete)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path), ["note.txt"])
    }

    func testFailedTrashDoesNotCountSavings() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try item("note.txt", root: root)
        let store = try SQLiteStore.inMemory()
        let executor = ReviewExecutor(
            store: store, access: FolderAccess(store: store), photos: PhotoLibraryService(),
            trash: FixtureTrash(folder: root, shouldFail: true))
        let event = await executor.apply(
            ReviewDecision(item: record, choice: .trash), tool: .large, operationID: "failure")
        XCTAssertEqual(event.state, .failed)
        XCTAssertEqual(event.savings, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(record.url).path))
    }

    func testResetReviewHistoryPreservesActivityAndSnapshots() async throws {
        let store = try SQLiteStore.inMemory()
        let record = ReviewItem(id: "test", source: .photos("fixture"), name: "test", kind: .image, bytes: 10)
        var event = ActivityEvent(tool: .swipe, item: record, action: "trash")
        event.state = .complete
        try await store.saveActivity(event)
        try await store.saveCleanupState(["test": ReviewChoice.keep], key: "review:scope")
        try await store.saveCleanupSnapshot(
            CleanupSnapshot(id: "day", scopeID: "scope", date: Date(), bytes: 10, count: 1))
        try await store.resetReviewHistory()
        let history = try await store.loadCleanupState([String: ReviewChoice].self, key: "review:scope")
        let events = try await store.cleanupActivity()
        let snapshots = try await store.cleanupSnapshots(scopeID: "scope")
        XCTAssertNil(history)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(snapshots.count, 1)
    }

    @MainActor func testSkipIsNotPersistedAsReviewedAndDateFilterIncludesWholeDay() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try item("note.txt", root: root)
        let model = CleanupModel(store: try SQLiteStore.inMemory())
        model.scope.roots = [root]
        model.result = AnalysisResult(
            generation: UUID(), scopeID: model.scope.id, settings: model.settings,
            items: [record], groups: [])
        await model.startSession()
        await model.decide(.skip)
        XCTAssertTrue(model.reviewed.isEmpty)
        XCTAssertNil(model.session?.current)
        model.filter = .beforeDate
        model.filterDate = record.modifiedAt ?? Date()
        XCTAssertEqual(model.filteredItems().count, 1)
    }

    func testUnsupportedCompressionKeepsOriginal() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try item("invalid.jpg", root: root)
        let source = try XCTUnwrap(record.url)
        do {
            _ = try await MediaCompressionService().compress(
                record, source: source, destination: root,
                settings: CleanupSettings()
            ) { _ in }
            XCTFail("Invalid image should fail verification")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["invalid.jpg"])
        }
    }

    func testInventoryCancellationDoesNotPublishPartialResults() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<100 { _ = try item("\(index).txt", root: root) }
        let inventory = ReviewInventory(access: FolderAccess(store: try SQLiteStore.inMemory()))
        var scope = ReviewScope()
        scope.roots = [root]
        let approvedScope = scope
        let task = Task { try await inventory.scan(approvedScope) { _ in } }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled scan should throw")
        } catch is CancellationError {} catch { XCTFail(error.localizedDescription) }
    }
}
