import Foundation
import XCTest

@testable import MacOSCleanerAppKit
@testable import MacOSCleanerCore

@MainActor
final class CleanupReviewFilterTests: XCTestCase {
    private func model() throws -> CleanupModel {
        let model = CleanupModel(store: try SQLiteStore.inMemory())
        let root = URL(fileURLWithPath: "/tmp/ReviewFilters")
        model.scope.roots = [root]
        let names = ["first.txt", "Nested/second.txt", "Nested/Deeper/third.txt"]
        let items = names.enumerated().map { index, name in
            var item = ReviewItem(
                id: "\(index)", source: .file(root.appendingPathComponent(name)),
                name: name, kind: .document, bytes: Int64(100 - index * 20))
            item.modifiedAt = Date(timeIntervalSince1970: Double(100 + index))
            return item
        }
        model.result = AnalysisResult(
            generation: UUID(), scopeID: model.scope.id,
            settings: model.settings, items: items, groups: [])
        return model
    }

    func testFiltersOrderByDateSizeAndRecursiveSubfolder() throws {
        let model = try model()
        model.filter = .everything
        XCTAssertEqual(model.filteredItems().map(\.id), ["2", "1", "0"])
        model.filter = .largest
        XCTAssertEqual(model.filteredItems().map(\.id), ["0", "1", "2"])
        model.filter = .subfolder
        model.filterFolder = URL(fileURLWithPath: "/tmp/ReviewFilters/Nested")
        XCTAssertEqual(model.filteredItems().map(\.id), ["2", "1"])
        model.filter = .unreviewed
        let item = try XCTUnwrap(model.result?.items.first)
        model.reviewed[item.reviewKey] = .keep
        XCTAssertEqual(model.filteredItems().map(\.id), ["2", "1"])
    }

    func testScopeChangeCannotReuseAnOldScanForNewDraft() async throws {
        let model = try model()
        model.scope.roots = [URL(fileURLWithPath: "/tmp/DifferentFolder")]
        await model.startSession()
        XCTAssertNil(model.session)
    }

    func testSwipeDraftKeepsOneMemberOfEveryGroup() async throws {
        let model = try model()
        model.result?.groups = [AnalysisGroup(tool: .duplicates, memberIDs: ["1", "2"], bestID: "1", explanation: "")]
        await model.startSession()
        await model.decide(.trash)
        XCTAssertEqual(model.session?.pendingChanges.count, 1)
        await model.decide(.trash)
        XCTAssertEqual(model.session?.pendingChanges.count, 1)
        XCTAssertEqual(model.session?.current?.id, "1")
        XCTAssertNotNil(model.error)
        let draft = try await model.store.loadCleanupState(ReviewSession.self, key: "draft")
        XCTAssertEqual(draft?.protectedGroups?.count, 1)
    }

    func testCompressionPresetDoesNotInvalidateMediaAnalysis() async throws {
        let model = try model()
        model.settings.imageQuality = .small
        await model.saveSettings()
        XCTAssertEqual(model.result?.isFresh, true)
        model.settings.similarSeconds = 9
        await model.saveSettings()
        XCTAssertEqual(model.result?.isFresh, false)
    }

    func testConfirmationRejectsAnotherScanAndScopeChangesInvalidateBadges() throws {
        let model = try model()
        let batch = try XCTUnwrap(model.makeBatch(items: model.result?.items ?? [], tool: .swipe))
        XCTAssertTrue(model.validate(batch))
        model.result?.generation = UUID()
        XCTAssertFalse(model.validate(batch))
        model.selection = ["1"]
        model.scope.roots = [URL(fileURLWithPath: "/tmp/OtherScope")]
        XCTAssertEqual(model.result?.isFresh, false)
        XCTAssertTrue(model.selection.isEmpty)
    }

    func testCompressionUsesOnlyConfirmedItemsAndSettings() async throws {
        let model = try model()
        model.result?.items[0].kind = .image
        model.result?.items[1].kind = .image
        model.selection = ["0", "1", "2"]
        let item = try XCTUnwrap(model.result?.items.first)
        let batch = try XCTUnwrap(model.makeBatch(items: [item], tool: .imageCompression))
        model.settings.imageQuality = .small
        model.selection = ["1"]
        model.compressSelection(batch)
        XCTAssertEqual(model.jobs.map(\.item.id), ["0"])
        XCTAssertEqual(batch.settings.imageQuality, .balanced)
        await finish(model)
        XCTAssertEqual(model.jobs.count, 1)
        XCTAssertEqual(model.jobs.first?.event?.state, .failed)
    }

    func testApplyingDraftLocksDecisionsAcrossRelaunch() async throws {
        let model = try model()
        await model.startSession()
        await model.decide(.skip)
        await model.decide(.keep)
        await model.decide(.trash)
        await model.commitSession()
        await finish(model)
        XCTAssertNil(model.notice)
        XCTAssertNotNil(model.session?.applicationStartedAt)
        await model.undoDecision()
        XCTAssertEqual(model.session?.decisions.count, 3)
        let relaunched = CleanupModel(store: model.store)
        await relaunched.load()
        XCTAssertNotNil(relaunched.session?.applicationStartedAt)
        XCTAssertEqual(relaunched.sessionResults.count, 1)
        await relaunched.undoDecision()
        XCTAssertEqual(relaunched.session?.decisions.count, 3)
        await relaunched.resetHistory()
        XCTAssertNil(relaunched.session)
        XCTAssertTrue(relaunched.sessionResults.isEmpty)
        XCTAssertEqual(relaunched.activity.count, 1)
    }

    func testIncompleteDraftCannotExecute() async throws {
        let model = try model()
        await model.startSession()
        await model.decide(.trash)
        await model.commitSession()
        XCTAssertFalse(model.isBusy)
        XCTAssertNil(model.session?.applicationStartedAt)
        let events = try await model.store.cleanupActivity()
        XCTAssertTrue(events.isEmpty)
    }

    private func finish(_ model: CleanupModel) async {
        for _ in 0..<200 where model.isBusy {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.isBusy)
    }
}
