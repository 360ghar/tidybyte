import XCTest
import SwiftData
@testable import Tidybyte

/// Regression coverage for the swipe-flow audit fixes: back-to-back swipes
/// (SWIPE-05), picker-guarded undo (SWIPE-06), pending-deletion exposure
/// (SWIPE-02), retry state reset (SWIPE-09), predicate-based swipe-record
/// upsert (SWIPE-03), and the empty-commit no-op (SWIPE-08).
@MainActor
final class SwipeFlowRegressionTests: XCTestCase {

    // Held for the lifetime of the test so the in-memory store (and the view
    // model's ModelContext, which is this container's mainContext) stays valid.
    private var container: ModelContainer!

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private func makeViewModel(assetCount: Int = 3) throws -> SwipeSessionViewModel {
        let schema = Schema([SwipeRecord.self, CompressionRecord.self, StorageSnapshot.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        let viewModel = SwipeSessionViewModel(
            filter: .allMedia,
            photoService: PhotoLibraryService(),
            modelContext: container.mainContext
        )
        viewModel.assets = (0..<assetCount).map { makeAsset(id: "asset-\($0)") }
        return viewModel
    }

    // MARK: - SWIPE-05: back-to-back swipes

    /// A swipe applies its decision at commit time (the fling is only visual),
    /// so two fast swipes must each land on their own card.
    func testBackToBackSwipesAttributeToTheirOwnCards() throws {
        let vm = try makeViewModel()

        vm.swipeLeft()
        vm.swipeRight()

        XCTAssertEqual(vm.currentIndex, 2)
        XCTAssertEqual(vm.pendingDeletionIds, ["asset-0"])
        XCTAssertEqual(vm.undoStack.map(\.asset.id), ["asset-0", "asset-1"])
        XCTAssertEqual(vm.undoStack.map(\.decision), [.deleted, .kept])
    }

    func testSwipeDirectionCommitPolicy() {
        let width: CGFloat = 300 // commit threshold 120
        func resolve(_ t: CGSize, _ p: CGSize = .zero) -> SwipeDirection? {
            SwipeDirection.resolve(translation: t, predicted: p, cardWidth: width, cardHeight: width)
        }
        XCTAssertEqual(resolve(CGSize(width: 130, height: 0)), .keep)
        XCTAssertEqual(resolve(CGSize(width: -130, height: 0)), .delete)
        XCTAssertEqual(resolve(CGSize(width: 40, height: 0), CGSize(width: 600, height: 0)), .keep, "A fast flick commits")
        XCTAssertEqual(resolve(CGSize(width: -130, height: -130)), .delete, "A diagonal drag resolves horizontally")
        XCTAssertEqual(resolve(CGSize(width: 10, height: -130)), .album)
        XCTAssertNil(resolve(CGSize(width: 60, height: -60)), "A short drag snaps back")
    }

    /// The up-swipe's threshold is capped by the card's height: on a deck that
    /// is short relative to its width (a squat card area), a width-derived
    /// threshold can exceed the card itself, which would make Add to Album
    /// unreachable. The cap never engages on a normal card, where the two
    /// thresholds are equal.
    func testAlbumThresholdIsCappedByCardHeight() {
        func resolve(_ height: CGFloat) -> SwipeDirection? {
            // Width 600 → 240pt horizontal threshold; height 100 → 40pt capped
            // vertical threshold.
            SwipeDirection.resolve(
                translation: CGSize(width: 0, height: height),
                predicted: .zero,
                cardWidth: 600,
                cardHeight: 100
            )
        }
        XCTAssertEqual(resolve(-45), .album, "45pt of up-travel commits on a 100pt-tall card")
        XCTAssertNil(resolve(-35), "Under the capped threshold the card snaps back")
        XCTAssertEqual(resolve(-240), .album)
    }

    /// The cost of the cap, bounded: with the vertical threshold below the
    /// horizontal one, an up-and-sideways drag must still be unambiguous before
    /// it files the photo. A drag that is wider than it is tall keeps snapping
    /// back, exactly as it did when both axes shared one threshold.
    func testAlbumCapDoesNotTurnAnAmbiguousDiagonalIntoAFiling() {
        func resolve(_ dx: CGFloat, _ dy: CGFloat) -> SwipeDirection? {
            SwipeDirection.resolve(
                translation: CGSize(width: dx, height: dy),
                predicted: .zero,
                cardWidth: 600, // 240pt horizontal threshold
                cardHeight: 100 // 40pt capped vertical threshold
            )
        }
        XCTAssertNil(resolve(100, -45), "Past the cap but wider than it is tall: snap back, not file")
        XCTAssertEqual(resolve(0, -45), .album, "Straight up still files")
        XCTAssertEqual(resolve(20, -60), .album, "Mostly-up still files")
        XCTAssertEqual(resolve(250, -45), .keep, "Past the horizontal threshold the horizontal branch wins, as before")
    }

    /// With no measured height (before the deck has laid out), the width-derived
    /// threshold stands rather than collapsing to zero.
    func testAlbumThresholdKeepsWidthDerivedValueWithoutCardHeight() {
        func resolve(_ height: CGFloat) -> SwipeDirection? {
            SwipeDirection.resolve(
                translation: CGSize(width: 0, height: height),
                predicted: .zero,
                cardWidth: 300,
                cardHeight: 0
            )
        }
        XCTAssertEqual(resolve(-130), .album, "The 120pt width-derived threshold still applies")
        XCTAssertNil(resolve(-60))
    }

    func testFlingVelocityIsRelativeAndClamped() {
        let start = CGSize(width: 100, height: 0)
        let target = SwipeDirection.keep.flingOffset(from: start, distance: 1000)
        XCTAssertEqual(target, CGSize(width: 1000, height: 0))
        XCTAssertEqual(SwipeDirection.relativeVelocity(CGSize(width: 1800, height: 0), from: start, to: target), 2, accuracy: 0.001)
        XCTAssertEqual(SwipeDirection.relativeVelocity(CGSize(width: -500, height: 0), from: start, to: target), 0, "A throw against the direction starts from rest")
        XCTAssertEqual(SwipeDirection.relativeVelocity(CGSize(width: 90_000, height: 0), from: start, to: target), 10)
    }

    // MARK: - SWIPE-06: undo blocked while album picker is presented

    func testUndoIsBlockedWhileAlbumPickerPresented() async throws {
        let vm = try makeViewModel()
        vm.swipeLeft() // deletion pending → undo stack non-empty
        XCTAssertEqual(vm.undoStack.count, 1)

        vm.keepWithAlbum() // opens the album picker for the next card
        XCTAssertTrue(vm.showAlbumPicker)

        await vm.undo() // must be a no-op: the deck must not rewind under the sheet

        XCTAssertEqual(vm.undoStack.count, 1, "Undo must not consume the entry while the picker is up")
        XCTAssertEqual(vm.currentIndex, 1, "The deck must not rewind while the picker is presented (it also does not advance until the album choice is resolved)")
        XCTAssertEqual(vm.pendingDeletionIds, ["asset-0"], "Pending deletions must be untouched")
    }

    // MARK: - SWIPE-02: pending-deletion exposure

    func testHasPendingDeletionsReflectsPendingIdsAndCommitState() throws {
        let vm = try makeViewModel()
        XCTAssertFalse(vm.hasPendingDeletions)

        vm.swipeLeft()
        XCTAssertTrue(vm.hasPendingDeletions)

        vm.deletionCommitted = true
        XCTAssertFalse(vm.hasPendingDeletions, "Committed deletions are no longer pending")

        vm.deletionCommitted = false
        vm.discardPendingDeletions()
        XCTAssertFalse(vm.hasPendingDeletions, "Discarded deletions are no longer pending")
    }

    // MARK: - SWIPE-09: retry resets load state

    func testRetryLoadClearsLoadedState() throws {
        let vm = try makeViewModel()
        // `hasLoadedInitialAssets` starts false and is private(set); the
        // meaningful regression is that retryLoad() resets the derived states
        // so loadAssetsIfNeeded() will re-run.
        vm.allPhotosAlreadySwiped = true
        vm.isLoading = true

        vm.retryLoad()

        XCTAssertFalse(vm.hasLoadedInitialAssets, "Retry must force a fresh load")
        XCTAssertFalse(vm.allPhotosAlreadySwiped)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - SWIPE-03: predicate-based upsert round-trip

    func testSwipeRecordUpsertRoundTrip() throws {
        let vm = try makeViewModel()

        vm.skip() // asset-0: insert via the predicate-based fetch

        let records = try container.mainContext.fetch(FetchDescriptor<SwipeRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.assetLocalIdentifier, "asset-0")
        XCTAssertEqual(records.first?.decision, .skipped)

        vm.skip() // asset-1: second id, second insert
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<SwipeRecord>()).count, 2)
    }

    func testSwipeRecordUpsertUpdatesExistingRecordViaPredicate() throws {
        let vm = try makeViewModel()

        vm.skip() // asset-0
        vm.currentIndex = 0 // rewind to the same asset
        vm.skip() // same asset again — must update in place, not duplicate

        let records = try container.mainContext.fetch(FetchDescriptor<SwipeRecord>())
        XCTAssertEqual(records.count, 1, "Re-skipping the same asset must upsert, not insert a duplicate")
        XCTAssertEqual(records.first?.assetLocalIdentifier, "asset-0")
    }

    // MARK: - SWIPE-08: empty commit is a no-op

    func testCommitDeletionsWithNoPendingIsNoOp() async throws {
        let vm = try makeViewModel()
        XCTAssertFalse(vm.deletionCommitted)

        await vm.commitDeletions()

        XCTAssertFalse(vm.deletionCommitted, "Committing zero pending deletions must be a no-op")
        XCTAssertFalse(vm.isDeletingBatch)
        XCTAssertFalse(vm.hasPendingDeletions)
    }

    // MARK: - RTL stamps: the stamp must name the action that commits

    /// In a left-to-right layout a right-drag keeps the photo, so KEEP is the
    /// stamp that lights up.
    func testStampOpacitiesLTRRightDragShowsKeep() {
        let stamps = SwipeDirection.stampOpacities(offset: CGSize(width: 90, height: 0), isRightToLeft: false)
        XCTAssertGreaterThan(stamps.keep, 0)
        XCTAssertEqual(stamps.delete, 0)
    }

    /// The destructive regression: in Arabic or Hebrew the SAME right-drag
    /// deletes the photo, because `resolve` mirrors the horizontal axis there.
    /// Direction-blind stamps showed KEEP while the photo was deleted.
    func testStampOpacitiesRTLRightDragShowsDelete() {
        let stamps = SwipeDirection.stampOpacities(offset: CGSize(width: 90, height: 0), isRightToLeft: true)
        XCTAssertGreaterThan(stamps.delete, 0)
        XCTAssertEqual(stamps.keep, 0)
    }

    /// Full strength at 150pt of drag, clamped above it, linear below, and
    /// nothing lit at rest.
    func testStampOpacitiesRampAndClamp() {
        func keep(_ width: CGFloat) -> Double {
            SwipeDirection.stampOpacities(offset: CGSize(width: width, height: 0), isRightToLeft: false).keep
        }
        XCTAssertEqual(keep(75), 0.5)
        XCTAssertEqual(keep(150), 1.0)
        XCTAssertEqual(keep(900), 1.0)
        XCTAssertEqual(
            SwipeDirection.stampOpacities(offset: .zero, isRightToLeft: true).delete,
            0,
            "a drag that has not moved must light no stamp"
        )
    }

    /// The guard that matters: for a threshold-crossing drag in either direction
    /// and either layout direction, the lit stamp names the action `resolve`
    /// commits. A drag under the threshold has not committed yet, so its stamp
    /// is only a preview of the side it would commit on.
    func testStampOpacitiesAgreeWithResolve() {
        let width: CGFloat = 300 // commit threshold 120
        for isRightToLeft in [false, true] {
            for drag in [CGSize(width: 200, height: 0), CGSize(width: -200, height: 0)] {
                let direction = SwipeDirection.resolve(
                    translation: drag,
                    predicted: .zero,
                    cardWidth: width,
                    cardHeight: width,
                    isRightToLeft: isRightToLeft
                )
                let stamps = SwipeDirection.stampOpacities(offset: drag, isRightToLeft: isRightToLeft)
                let lit: SwipeDirection? = stamps.keep > 0 ? .keep : (stamps.delete > 0 ? .delete : nil)
                XCTAssertEqual(
                    lit,
                    direction,
                    "RTL=\(isRightToLeft) drag=\(drag) must show the action resolve commits"
                )
                XCTAssertFalse(
                    stamps.keep > 0 && stamps.delete > 0,
                    "DELETE and KEEP must never be lit at the same time"
                )
            }
        }
    }

    /// A drag that has not reached the commit threshold lights a stamp without
    /// committing anything. The stamp still has to sit on the mirrored side, so
    /// the preview never contradicts the release.
    func testSubThresholdStampPreviewsTheMirroredSide() {
        let width: CGFloat = 300 // commit threshold 120
        for isRightToLeft in [false, true] {
            for drag in [CGSize(width: 60, height: 0), CGSize(width: -60, height: 0)] {
                XCTAssertNil(
                    SwipeDirection.resolve(
                        translation: drag,
                        predicted: .zero,
                        cardWidth: width,
                        cardHeight: width,
                        isRightToLeft: isRightToLeft
                    ),
                    "60pt is under the 120pt threshold"
                )
                let stamps = SwipeDirection.stampOpacities(offset: drag, isRightToLeft: isRightToLeft)
                let lit: SwipeDirection? = stamps.keep > 0 ? .keep : (stamps.delete > 0 ? .delete : nil)
                let forward = isRightToLeft ? -drag.width : drag.width
                let expected: SwipeDirection = forward > 0 ? .keep : .delete
                XCTAssertEqual(
                    lit,
                    expected,
                    "RTL=\(isRightToLeft) drag=\(drag) previews the wrong side"
                )
            }
        }
    }

    // MARK: - Helpers

    private func makeAsset(id: String) -> AssetSummary {
        AssetSummary(
            id: id,
            mediaType: .photo,
            creationDate: .now,
            modificationDate: .now,
            pixelWidth: 4032,
            pixelHeight: 3024,
            duration: 0,
            fileSize: 8_000_000,
            filename: "\(id).jpg",
            isFavorite: false,
            isBurst: false,
            burstIdentifier: nil,
            isLivePhoto: false,
            isScreenshot: false,
            isLocallyAvailable: true
        )
    }
}
