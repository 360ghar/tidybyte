import XCTest
import SwiftData
@testable import Tidybyte

@MainActor
final class CleanupFeaturesTests: XCTestCase {
    private func asset(_ id: String = "a", size: Int64 = 1_000, type: MediaType = .photo,
                       screenshot: Bool = false, favorite: Bool = false) -> AssetSummary {
        AssetSummary(id: id, mediaType: type, creationDate: Date(timeIntervalSince1970: 100), modificationDate: nil,
                     pixelWidth: 100, pixelHeight: 100, duration: 0, fileSize: size, filename: "IMG_1.JPG",
                     isFavorite: favorite, isBurst: false, burstIdentifier: nil, isLivePhoto: false,
                     isScreenshot: screenshot, isLocallyAvailable: true)
    }

    func testReminderUsesDatedCountsWithoutDoubleCountingLargeScreenshots() {
        let stats = MediaLibraryStats.build(from: [asset(size: 20_000, screenshot: true), asset("video", size: 30_000, type: .video)], largeFileThresholdBytes: 10_000)
        let body = NotificationService.reminderBody(snapshot: .init(stats: stats, date: Date(timeIntervalSince1970: 1_790_294_400), isLimited: true))
        XCTAssertTrue(body.contains("Last scan,"))
        XCTAssertTrue(body.contains("1 screenshot"))
        XCTAssertTrue(body.contains("1 large file"))
        XCTAssertTrue(body.contains("selected photos"))
        XCTAssertTrue(body.contains(Int64(20_000).formattedFileSize))
    }

    func testReminderOmitsPartialSizesAndUsesGenericTextForEmptySnapshots() {
        let stats = MediaLibraryStats.build(from: [asset("a", size: 5_000, screenshot: true), asset("b", size: 0, screenshot: true)], largeFileThresholdBytes: 10_000)
        let body = NotificationService.reminderBody(snapshot: .init(stats: stats, date: .now, isLimited: false))
        XCTAssertTrue(body.contains("2 screenshots"))
        XCTAssertFalse(body.contains("("))
        XCTAssertEqual(NotificationService.reminderBody(snapshot: nil), NotificationService.reminderBody(snapshot: .init(stats: MediaLibraryStats(), date: .now, isLimited: false)))
    }

    func testDeletionNoticeCountsOnlyConfirmedIDsAndSurvivesUnavailableHistoryStore() {
        CleanupLedger.shared.detach()
        defer { CleanupLedger.shared.detach() }
        let outcome = PhotoDeletionOutcome(deletedIds: ["deleted"], alreadyAbsentIds: ["missing"])
        XCTAssertEqual(outcome.removedIds, ["deleted", "missing"])
        CleanupLedger.shared.record(kind: .chatMedia, deletedIds: outcome.deletedIds, sizeOf: { _ in 1_000 })
        let first = CleanupLedger.shared.deletionNotice
        XCTAssertEqual(first?.itemCount, 1)
        XCTAssertEqual(first?.knownBytes, 1_000)
        CleanupLedger.shared.publishDeletion(deletedIds: [], sizeOf: { _ in 100 })
        XCTAssertEqual(CleanupLedger.shared.deletionNotice, first)
        CleanupLedger.shared.publishDeletion(deletedIds: ["next"], sizeOf: { _ in 2_000 })
        CleanupLedger.shared.dismissDeletionNotice(id: first?.id)
        XCTAssertEqual(CleanupLedger.shared.deletionNotice?.knownBytes, 2_000)
    }

    func testPartialDeletionAndUnknownSizesDoNotClaimRemainingOrFreedBytes() {
        let error = PhotoServiceError.partialDeletion(succeededIds: ["ok"], failedCount: 1, alreadyAbsentIds: ["gone"])
        XCTAssertEqual(error.deletionOutcome?.deletedIds, ["ok"])
        XCTAssertEqual(error.deletionOutcome?.removedIds, ["ok", "gone"])
        let notice = DeletionNotice(sizes: [2_000, 0, -1])
        XCTAssertEqual(notice.knownBytes, 2_000)
        XCTAssertEqual(notice.unknownSizeCount, 2)
        XCTAssertTrue(notice.message.contains("moved 3 items"))
        XCTAssertFalse(notice.message.contains("still"))
        XCTAssertFalse(notice.message.contains("freed"))
    }

    func testRecordingFilenameBoundariesAndUnknownSizeSelection() {
        for filename in ["RPReplay_Final123.MP4", "rpreplay_final.mp4"] {
            XCTAssertTrue(PhotoLibraryService.isScreenRecordingFilename(filename))
        }
        for filename in ["IMG_123.MP4", "prefixRPReplay_Final.MP4", "RPReplay_Final.MP4.jpg"] {
            XCTAssertFalse(PhotoLibraryService.isScreenRecordingFilename(filename))
        }
        let vm = MediaCleanerViewModel(tool: .screenRecordings)
        vm.assets = [asset("unknown", size: 0, type: .video), asset("large", size: 2_000, type: .video)]
        XCTAssertEqual(vm.filteredAssets.map(\.id), ["large", "unknown"])
        vm.selectedIDs = ["large", "unknown", "stale"]
        XCTAssertEqual(vm.visibleSelectedIDs, ["large", "unknown"])
        vm.mediaFilter = .photos
        XCTAssertTrue(vm.visibleSelectedIDs.isEmpty)
    }

    func testChatAlbumMatchingAndPersistedEmptySelection() {
        XCTAssertTrue(ChatAlbumSelection.isRecognized("  WhatsApp   Business\n"))
        XCTAssertTrue(ChatAlbumSelection.isRecognized("TELEGRAM"))
        XCTAssertFalse(ChatAlbumSelection.isRecognized("Telegram holiday"))
        let suite = "ChatAlbumTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let albums = [AlbumInfo(id: "chat", title: "WhatsApp", count: 1, type: .userAlbum), AlbumInfo(id: "other", title: "Renamed", count: 1, type: .userAlbum)]
        XCTAssertEqual(ChatAlbumSelection.selectedIDs(in: albums, defaults: defaults), ["chat"])
        defaults.set(["other", "missing"], forKey: AppPreferences.Key.chatAlbumIDs)
        XCTAssertEqual(ChatAlbumSelection.selectedIDs(in: albums, defaults: defaults), ["other"])
        defaults.set([String](), forKey: AppPreferences.Key.chatAlbumIDs)
        XCTAssertTrue(ChatAlbumSelection.selectedIDs(in: albums, defaults: defaults).isEmpty)
    }

    func testCameraFormatOverlapDoesNotChangeSavings() {
        var both = asset(size: 2_000, type: .video)
        both.isCinematic = true
        both.isSpatial = true
        both.isScreenRecording = true
        let before = MediaLibraryStats.build(from: [asset(size: 2_000, type: .video)], largeFileThresholdBytes: 1_000)
        let after = MediaLibraryStats.build(from: [both], largeFileThresholdBytes: 1_000)
        XCTAssertEqual(before.reclaimableBytes, after.reclaimableBytes)
        XCTAssertEqual(CameraFormatInsight.build(from: [both]).map(\.count), [1, 1])
    }

    func testQualityBoundariesAndWorstShotEligibility() {
        XCTAssertFalse(LensSmudgeResult(confidence: 0.79).isSmudged)
        XCTAssertTrue(LensSmudgeResult(confidence: 0.8).isSmudged)
        XCTAssertFalse(AestheticsResult(score: 0, isUtility: false).isLowQuality)
        XCTAssertTrue(AestheticsResult(score: -0.01, isUtility: false).isLowQuality)
        XCTAssertFalse(AestheticsResult(score: -1, isUtility: true).isLowQuality)
        XCTAssertFalse(AestheticsResult(score: .nan, isUtility: false).isLowQuality)
        XCTAssertFalse(SwipeSessionViewModel.isWorstShotCandidate(asset(favorite: true)))
        XCTAssertFalse(SwipeSessionViewModel.isWorstShotCandidate(asset(screenshot: true)))
        XCTAssertFalse(SwipeSessionViewModel.isWorstShotCandidate(asset(type: .video)))
        let score = AestheticsResult(score: -0.2, isUtility: false)
        let sorted = [(asset: asset("b"), result: score), (asset: asset("a"), result: score)].sorted(by: SwipeSessionViewModel.worstShotOrder)
        XCTAssertEqual(sorted.map(\.asset.id), ["a", "b"])
    }

    func testSearchGroupsExclusionsAndUnknownConcepts() {
        let vocabulary: Set<String> = ["dog", "puppy", "beach", "cat"]
        let query = PhotoSearchQuery(requiredGroups: [["Dog", "puppy"], ["beach"]], excludedLabels: ["cat"]).validated(vocabulary: vocabulary)!
        XCTAssertTrue(query.matches(labels: ["dog": 0.9, "beach": 0.7]))
        XCTAssertFalse(query.matches(labels: ["dog": 0.9]))
        XCTAssertFalse(query.matches(labels: ["dog": 0.9, "beach": 0.7, "cat": 0.8]))
        XCTAssertNil(PhotoSearchQuery(requiredGroups: [["dog"], ["unknown"]], excludedLabels: []).validated(vocabulary: vocabulary))
        XCTAssertNotNil(PhotoSearchQuery(requiredGroups: [["dog"]], excludedLabels: ["unknown"]).validated(vocabulary: vocabulary))
        XCTAssertNil(PhotoSearchQuery.keywords("", vocabulary: vocabulary))
        XCTAssertNotNil(PhotoSearchQuery.keywords("dog beach", vocabulary: vocabulary))
    }

    func testSearchRejectsLateResultsAfterTypingOrIndexChanges() async {
        let started = expectation(description: "old search starts")
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        let vm = SmartCategoriesViewModel(search: { _, _ in
            started.fulfill()
            for await _ in gate { break }
            return PhotoSearchResult(query: .init(requiredGroups: [["dog"]], excludedLabels: []), message: "old result")
        })
        vm.categorizedPhotos = [CategorizedPhoto(id: "a", asset: asset(), categories: [.other], contentLabels: ["dog": 0.9], wasAnalyzed: true)]
        vm.searchText = "dog"
        let task = vm.submitSearch()
        await fulfillment(of: [started], timeout: 2)
        vm.searchText = "beach"
        vm.categorizedPhotos = []
        continuation.finish()
        await task?.value
        XCTAssertFalse(vm.isSearching)
        XCTAssertNil(vm.searchMessage)
        XCTAssertTrue(vm.filteredPhotos.isEmpty)
    }

    func testReasonsRejectInventedFactsAndLateCardResults() throws {
        XCTAssertNil(PhotoReviewReason.validatedChoice("blurry", allowed: [.large]))
        XCTAssertNil(PhotoReviewReason.validatedChoice("delete_everything", allowed: [.large]))
        let container = try ModelContainer(for: SwipeRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let vm = SwipeSessionViewModel(filter: .allMedia, photoService: PhotoLibraryService(), modelContext: container.mainContext)
        let first = asset("first"), second = asset("second")
        vm.assets = [first, second]
        vm.currentIndex = 1
        vm.applyReviewReason("Old reason", for: first, epoch: ScanResults.epoch)
        XCTAssertNil(vm.reviewReason)
        vm.applyReviewReason("Current reason", for: second, epoch: ScanResults.epoch)
        XCTAssertEqual(vm.reviewReason, "Current reason")
        vm.currentIndex = 0
        XCTAssertNil(vm.reviewReason)
        vm.applyReviewReason("Stale analysis", for: first, epoch: ScanResults.epoch - 1)
        XCTAssertNil(vm.reviewReason)
    }

    func testResourceSizeIsUnknownWhenAnyComponentIsMissing() {
        XCTAssertEqual(PhotoLibraryService.completeResourceSize([]), 0)
        XCTAssertEqual(PhotoLibraryService.completeResourceSize([2_000, 0]), 0)
        XCTAssertEqual(PhotoLibraryService.completeResourceSize([0, 3_000]), 0)
        XCTAssertEqual(PhotoLibraryService.completeResourceSize([2_000, -1]), 0)
        XCTAssertEqual(PhotoLibraryService.completeResourceSize([2_000, 3_000]), 5_000)
    }

    func testPermissionChangeClearsCountsAndRejectsPendingSearch() async {
        ScanResults.resetForTesting()
        defer { ScanResults.resetForTesting() }
        let started = expectation(description: "search starts")
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        let vm = SmartCategoriesViewModel(search: { _, _ in
            started.fulfill()
            for await _ in gate { break }
            return PhotoSearchResult(query: .init(requiredGroups: [["dog"]], excludedLabels: []), message: nil)
        })
        vm.categorizedPhotos = [CategorizedPhoto(id: "a", asset: asset(), categories: [.other], contentLabels: ["dog": 0.9], wasAnalyzed: true)]
        ScanResults.record(.chatMedia, count: 10)
        ScanResults.record(.blurry, count: 5, epoch: ScanResults.epoch)
        let oldEpoch = ScanResults.epoch
        vm.searchText = "dog"
        let task = vm.submitSearch()
        await fulfillment(of: [started], timeout: 2)

        let monitor = LibraryChangeMonitor()
        monitor.permissionDidChange()
        XCTAssertEqual(monitor.generation, 1)
        XCTAssertGreaterThan(ScanResults.epoch, oldEpoch)
        XCTAssertTrue(ScanResults.counts.isEmpty)
        ScanResults.record(.blurry, count: 5, epoch: oldEpoch)
        XCTAssertTrue(ScanResults.counts.isEmpty)
        continuation.finish()
        await task?.value
        XCTAssertFalse(vm.isSearching)
        XCTAssertTrue(vm.filteredPhotos.isEmpty)
        XCTAssertEqual(vm.searchMessage, "Your library changed. Scan again before searching.")
    }

    func testExclusionSearchDoesNotTreatUnanalyzedPhotosAsMatches() async {
        let vm = SmartCategoriesViewModel(search: { _, _ in
            PhotoSearchResult(query: .init(requiredGroups: [], excludedLabels: ["dog"]), message: nil)
        })
        vm.categorizedPhotos = [
            CategorizedPhoto(id: "cat", asset: asset("cat"), categories: [.other], contentLabels: ["cat": 0.9], wasAnalyzed: true),
            CategorizedPhoto(id: "dog", asset: asset("dog"), categories: [.other], contentLabels: ["dog": 0.9], wasAnalyzed: true),
            CategorizedPhoto(id: "unknown", asset: asset("unknown"), categories: [.savedFromApps], contentLabels: [:], wasAnalyzed: false)
        ]
        vm.searchText = "without dogs"
        await vm.submitSearch()?.value
        XCTAssertFalse(vm.isSearching)
        XCTAssertEqual(vm.filteredPhotos.map(\.id), ["cat"])
    }

    func testHiddenCompletionDoesNotSuppressNoticeOnAnotherTab() throws {
        let container = try ModelContainer(for: SwipeRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let vm = SwipeSessionViewModel(filter: .allMedia, photoService: PhotoLibraryService(), modelContext: container.mainContext)
        vm.showCompletion = true
        let navigation = AppNavigation()
        navigation.setActiveSwipeSession(vm)
        XCTAssertTrue(navigation.isShowingSwipeCompletion)
        navigation.selectedTab = .cleanup
        XCTAssertFalse(navigation.isShowingSwipeCompletion)
        navigation.setActiveSwipeSession(vm)
        XCTAssertTrue(navigation.isShowingSwipeCompletion)
        navigation.selectedTab = .swipe
        XCTAssertFalse(navigation.isShowingSwipeCompletion)
        navigation.setActiveSwipeSession(nil)
        XCTAssertFalse(navigation.isShowingSwipeCompletion)
    }

    func testStorageHistoryUsesScanCompletionDayAcrossMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startedAt = Date(timeIntervalSince1970: 86_399)
        let completedAt = Date(timeIntervalSince1970: 86_401)
        XCTAssertTrue(WidgetSnapshotCoordinator.shouldRecordStorageSnapshot(lastRecordedAt: nil, completedAt: completedAt, calendar: calendar))
        XCTAssertTrue(WidgetSnapshotCoordinator.shouldRecordStorageSnapshot(lastRecordedAt: startedAt, completedAt: completedAt, calendar: calendar))
        XCTAssertFalse(WidgetSnapshotCoordinator.shouldRecordStorageSnapshot(lastRecordedAt: completedAt, completedAt: completedAt.addingTimeInterval(60), calendar: calendar))
        XCTAssertTrue(WidgetSnapshotCoordinator.shouldRecordStorageSnapshot(lastRecordedAt: completedAt, completedAt: completedAt.addingTimeInterval(86_400), calendar: calendar))
    }

    func testDeclinedAndCancelledCleanupPreservesNoticeAndReconcilesAbsentItems() async {
        CleanupLedger.shared.detach()
        defer { CleanupLedger.shared.detach() }
        CleanupLedger.shared.publishDeletion(deletedIds: ["previous"], sizeOf: { _ in 2_000 })
        let previous = CleanupLedger.shared.deletionNotice
        var removed = Set<String>()
        let declined = await CleanupDeletion.delete(requestedIds: ["gone", "kept"], kind: .chatMedia,
            sizeById: ["gone": 1_000, "kept": 1_000], performDelete: { _ in
                throw PhotoServiceError.userDeclined(alreadyAbsentIds: ["gone"])
            }, apply: { removed = $0 })
        XCTAssertEqual(removed, ["gone"])
        XCTAssertEqual(declined.deletedCount, 0)
        XCTAssertEqual(declined.errorMessage, "Nothing was deleted.")
        XCTAssertEqual(CleanupLedger.shared.deletionNotice, previous)
        _ = await CleanupDeletion.delete(requestedIds: ["kept"], kind: .chatMedia,
            sizeById: [:], performDelete: { _ in throw CancellationError() }, apply: { _ in XCTFail("No removals on cancellation") })
        XCTAssertEqual(CleanupLedger.shared.deletionNotice, previous)
        _ = await CleanupDeletion.delete(requestedIds: ["kept", "failed"], kind: .chatMedia,
            sizeById: ["kept": 3_000], performDelete: { _ in
                throw PhotoServiceError.partialDeletion(succeededIds: ["kept"], failedCount: 1)
            }, apply: { _ in })
        XCTAssertEqual(CleanupLedger.shared.deletionNotice?.itemCount, 1)
        XCTAssertEqual(CleanupLedger.shared.deletionNotice?.knownBytes, 3_000)
    }

    func testSearchSurvivesUnchangedAndReducedIndex() async {
        defer { ScanResults.resetForTesting() }
        let vm = SmartCategoriesViewModel(search: { _, _ in
            PhotoSearchResult(query: .init(requiredGroups: [["dog"]], excludedLabels: []), message: "Search complete")
        })
        vm.categorizedPhotos = ["first", "second"].map {
            CategorizedPhoto(id: $0, asset: asset($0), categories: [.other], contentLabels: ["dog": 0.9], wasAnalyzed: true)
        }
        vm.searchText = "dog"
        await vm.submitSearch()?.value
        vm.retainUnchangedPhotos(["first", "second"])
        XCTAssertEqual(vm.filteredPhotos.count, 2)
        XCTAssertEqual(vm.searchMessage, "Search complete")
        vm.selectedIds = ["first", "second"]
        vm.retainUnchangedPhotos(["second"])
        XCTAssertEqual(vm.filteredPhotos.map(\.id), ["second"])
        XCTAssertEqual(vm.selectedIds, ["second"])
        XCTAssertEqual(vm.searchText, "dog")
    }

    func testDirectLabelSearchHandlesConnectorsButRejectsUnsupportedConditions() {
        let vocabulary: Set<String> = ["dog", "beach"]
        let query = PhotoSearchQuery.keywords("Show me a dog, on the beach!", vocabulary: vocabulary)
        XCTAssertEqual(query?.requiredGroups, [["dog"], ["beach"]])
        XCTAssertNil(PhotoSearchQuery.keywords("dog without cat", vocabulary: vocabulary))
        XCTAssertNil(PhotoSearchQuery.keywords("dog -beach", vocabulary: vocabulary))
        XCTAssertNil(PhotoSearchQuery.keywords("dog unknown", vocabulary: vocabulary))
        let fallback = LocalPhotoIntelligence.labelSearch("dog unknown", vocabulary: vocabulary, reason: "Local AI is unavailable.")
        XCTAssertNil(fallback.query)
        XCTAssertFalse(fallback.message?.contains("Using label search") == true)
        let exclusion = PhotoSearchQuery(requiredGroups: [], excludedLabels: ["cat"]).validated(vocabulary: vocabulary)
        XCTAssertTrue(exclusion?.matches(labels: ["dog": 0.9]) == true)
    }

    func testReminderDoesNotUseCountsFromAnotherPermissionScope() {
        let full = NotificationService.Snapshot(stats: MediaLibraryStats(), date: .now, isLimited: false)
        let limited = NotificationService.Snapshot(stats: MediaLibraryStats(), date: .now, isLimited: true)
        XCTAssertNotNil(NotificationService.authorizedSnapshot(full, permission: .authorized))
        XCTAssertNil(NotificationService.authorizedSnapshot(full, permission: .limited))
        XCTAssertNil(NotificationService.authorizedSnapshot(limited, permission: .authorized))
        XCTAssertNotNil(NotificationService.authorizedSnapshot(limited, permission: .limited))
        XCTAssertNil(NotificationService.authorizedSnapshot(full, permission: .denied))
        XCTAssertNil(NotificationService.authorizedSnapshot(limited, permission: .restricted))
    }

    func testSnapshotRetriesAreBoundedAndDateFollowsStatistics() async {
        defer { ScanResults.resetForTesting() }
        var calls = 0
        let changing = WidgetSnapshotCoordinator(statistics: {
            calls += 1
            ScanResults.invalidate()
            return MediaLibraryStats()
        }, photoAuthorization: { .authorized })
        let unavailable = await changing.currentSnapshot()
        XCTAssertNil(unavailable)
        XCTAssertEqual(calls, 2)
        var measuredAt = Date.distantFuture
        let stable = WidgetSnapshotCoordinator(statistics: {
            measuredAt = .now
            return MediaLibraryStats()
        }, photoAuthorization: { .limited })
        let snapshot = await stable.currentSnapshot()
        XCTAssertGreaterThanOrEqual(snapshot?.date ?? .distantPast, measuredAt)
        XCTAssertTrue(snapshot?.isLimited == true)
    }

    func testConcurrentSnapshotRequestsShareEnumeration() async {
        let started = expectation(description: "statistics start")
        let joined = expectation(description: "second caller starts")
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        var calls = 0
        let coordinator = WidgetSnapshotCoordinator(statistics: {
            calls += 1
            started.fulfill()
            for await _ in gate { break }
            return MediaLibraryStats()
        }, photoAuthorization: { .authorized })
        let first = Task { await coordinator.currentSnapshot() }
        await fulfillment(of: [started], timeout: 2)
        let second = Task {
            joined.fulfill()
            return await coordinator.currentSnapshot()
        }
        await fulfillment(of: [joined], timeout: 2)
        continuation.finish()
        let firstSnapshot = await first.value
        let secondSnapshot = await second.value
        XCTAssertNotNil(firstSnapshot)
        XCTAssertEqual(firstSnapshot?.date, secondSnapshot?.date)
        XCTAssertEqual(calls, 1)
    }

    func testCancellingLastRequesterCancelsSharedScan() async {
        let started = expectation(description: "scan starts")
        let cancelled = expectation(description: "shared scan cancels")
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        let coordinator = WidgetSnapshotCoordinator(statistics: {
            started.fulfill()
            return await withTaskCancellationHandler {
                for await _ in gate { break }
                return MediaLibraryStats()
            } onCancel: {
                cancelled.fulfill()
            }
        }, photoAuthorization: { .authorized })
        let request = Task { await coordinator.currentSnapshot() }
        await fulfillment(of: [started], timeout: 2)
        request.cancel()
        await fulfillment(of: [cancelled], timeout: 2)
        continuation.finish()
        let result = await request.value
        XCTAssertNil(result)
    }
}
