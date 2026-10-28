import AppKit
import Foundation
import MacOSCleanerCore
import Observation
import UserNotifications

@MainActor @Observable
final class CleanupModel {
    let store: SQLiteStore
    let access: FolderAccess
    let photos: PhotoLibraryService
    let executor: ReviewExecutor
    private let inventory: ReviewInventory
    private let analysis: MediaAnalysisService
    var scope = ReviewScope() {
        didSet {
            if scope != oldValue {
                result?.isFresh = false
                selection = []
            }
        }
    }
    var settings = CleanupSettings()
    var result: AnalysisResult?
    var session: ReviewSession?
    var reviewed: [String: ReviewChoice] = [:]
    var activity: [ActivityEvent] = []
    var snapshots: [CleanupSnapshot] = []
    var jobs: [CompressionJob] = []
    var progress = CleanupProgress("", completed: 0, total: 0)
    var isBusy = false
    var isSaving = false
    var error: String?
    var notice: String?
    var showsScope = false
    var selectedTool: CleanupTool?
    var selection = Set<String>()
    var selectedItem: ReviewItem?
    var sessionResults: [ActivityEvent] = []
    var completedSession: ReviewSession?
    var filter: ReviewFilter = .unreviewed
    var filterDate = Date()
    var filterFolder: URL?
    private var task: Task<Void, Never>?
    private var loaded = false
    private var monitoredGrants: [URL] = []
    private var freshness: CleanupFreshnessMonitor?
    private var changeGeneration = 0

    init(store: SQLiteStore) {
        self.store = store
        let access = FolderAccess(store: store)
        let photos = PhotoLibraryService()
        self.access = access
        self.photos = photos
        inventory = ReviewInventory(access: access)
        analysis = MediaAnalysisService(photos: photos, store: store)
        executor = ReviewExecutor(store: store, access: access, photos: photos)
    }

    func load() async {
        guard !loaded else { return }
        loaded = true
        do {
            scope = try await store.loadCleanupState(ReviewScope.self, key: "scope") ?? scope
            settings = try await store.loadCleanupState(CleanupSettings.self, key: "settings") ?? settings
            session = (try await store.loadCleanupState(ReviewSession?.self, key: "draft")).flatMap { $0 }
            result = try await store.loadCleanupState(AnalysisResult.self, key: "inventory")
            result?.isFresh = false
            reviewed = try await store.loadCleanupState([String: ReviewChoice].self, key: "review:" + scope.id) ?? [:]
            filter = settings.defaultFilter
            try await reloadHistory()
            if var draft = session {
                sessionResults = draft.pendingChanges.compactMap { decision in
                    activity.first { $0.id == draft.id + "|" + decision.item.id }
                }
                if !sessionResults.isEmpty, draft.applicationStartedAt == nil {
                    draft.applicationStartedAt = sessionResults.map(\.date).min()
                    try await store.saveCleanupState(Optional(draft), key: "draft")
                    session = draft
                }
            }
            if activity.contains(where: {
                $0.state == .prepared || $0.state == .outputReady || $0.state == .interrupted
                    || ($0.restoreStartedAt != nil && !$0.restored)
            }) {
                error = String(
                    localized: """
                        An earlier operation stopped. Check Activity before retrying. No changes \
                        will resume automatically.
                        """
                )
            }
        } catch {
            loaded = false
            self.error = error.localizedDescription
        }
    }

    func grant(_ urls: [URL]) async {
        do {
            for url in urls { try await access.grant(url) }
            result?.isFresh = false
            scope.roots =
                scope.mode == .folder
                ? Array(urls.prefix(1)) : Array(Set(scope.roots + urls)).sorted { $0.path < $1.path }
            try await store.saveCleanupState(scope, key: "scope")
        } catch { self.error = error.localizedDescription }
    }

    func scanChatFolder(_ url: URL) async {
        scope.mode = .folder
        scope.includesPhotos = false
        scope.exportedChatFolder = url
        await grant([url])
        if scope.roots == [url] { scan() }
    }

    func scan() {
        guard !isBusy, !scope.roots.isEmpty || scope.includesPhotos else {
            showsScope = true
            return
        }
        isBusy = true
        error = nil
        notice = nil
        result?.isFresh = false
        let scope = scope
        let settings = settings
        startMonitoring()
        let generation = changeGeneration
        task = Task {
            var grants: [URL] = []
            defer {
                for grant in grants { grant.stopAccessingSecurityScopedResource() }
                isBusy = false
                task = nil
            }
            do {
                for root in scope.roots { grants.append(try await access.acquire(root)) }
                for grant in monitoredGrants { grant.stopAccessingSecurityScopedResource() }
                monitoredGrants = []
                for root in scope.roots { monitoredGrants.append(try await access.acquire(root)) }
                try await store.saveCleanupState(scope, key: "scope")
                let report: @Sendable (CleanupProgress) async -> Void = { [self] value in
                    await MainActor.run { self.progress = value }
                }
                var items = try await inventory.scan(scope, progress: report)
                if scope.includesPhotos { items += try await photos.scan(progress: report) }
                var analyzed = try await analysis.analyze(
                    items, scopeID: scope.id, settings: settings, progress: report)
                try Task.checkCancellation()
                analyzed.isFresh =
                    generation == changeGeneration && self.scope.id == scope.id
                    && self.settings.analysisVersion == settings.analysisVersion
                try await store.saveCleanupState(analyzed, key: "inventory")
                result = analyzed
                reviewed =
                    try await store.loadCleanupState([String: ReviewChoice].self, key: "review:" + scope.id) ?? [:]
                let date = Calendar.current.startOfDay(for: Date())
                let snapshot = CleanupSnapshot(
                    id: scope.id + "|\(date.timeIntervalSince1970)", scopeID: scope.id,
                    date: date, bytes: items.reduce(0) { $0 + $1.bytes }, count: items.count)
                if analyzed.isFresh { try await store.saveCleanupSnapshot(snapshot) }
                try await reloadHistory()
                startMonitoring()
                try await updateReminder()
            } catch is CancellationError { result?.isFresh = false } catch { self.error = error.localizedDescription }
        }
    }

    func cancel() { task?.cancel() }

    func saveSettings() async {
        do {
            try await store.saveCleanupState(settings, key: "settings")
            if result?.settingsVersion != settings.analysisVersion {
                result?.isFresh = false
            } else {
                result?.settings = settings
            }
            try await updateReminder()
        } catch { self.error = error.localizedDescription }
    }

    func items(for tool: CleanupTool) -> [ReviewItem] {
        guard let result else { return [] }
        return MediaAnalysisService.candidates(tool, in: result)
    }

}

extension CleanupModel {
    func startSession(items: [ReviewItem]? = nil, tool: CleanupTool = .swipe) async {
        guard session == nil, let result, result.isFresh, result.scopeID == scope.id else { return }
        let candidates = items ?? filteredItems()
        var draft = ReviewSession(scopeID: scope.id, items: candidates, tool: tool)
        draft.protectedGroups = result.groups
        do {
            try await store.saveCleanupState(Optional(draft), key: "draft")
            session = draft
            sessionResults = []
            completedSession = nil
        } catch { self.error = error.localizedDescription }
    }

    func filteredItems() -> [ReviewItem] {
        let candidates = (result?.items ?? []).filter { item in
            switch filter {
            case .unreviewed: reviewed[item.reviewKey] == nil
            case .beforeDate:
                (item.modifiedAt ?? .distantFuture)
                    < (Calendar.current.date(
                        byAdding: .day, value: 1,
                        to: Calendar.current.startOfDay(for: filterDate)) ?? filterDate)
            case .subfolder:
                if let filterFolder, let url = item.url { ReviewSafety.contains(url, in: filterFolder) } else { false }
            case .everything, .largest: true
            }
        }
        return candidates.sorted {
            if filter == .largest, $0.bytes != $1.bytes { return $0.bytes > $1.bytes }
            if $0.modifiedAt != $1.modifiedAt {
                return ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast)
            }
            return $0.id < $1.id
        }
    }

    /// - Returns: true when the decision was recorded (callers register undo only then).
    @discardableResult
    func decide(_ choice: ReviewChoice, destination: URL? = nil) async -> Bool {
        guard !isSaving, !isBusy, var draft = session, draft.applicationStartedAt == nil,
            let item = draft.current
        else { return false }
        guard choice == .keep || choice == .skip || item.canChange else { return false }
        if choice == .trash {
            let removing = Set(draft.decisions.filter { $0.choice == .trash }.map(\.item.id)).union([item.id])
            if draft.protectedGroups?.contains(where: { $0.memberIDs.allSatisfy(removing.contains) }) == true {
                error = String(
                    localized: "Keep at least one member of each group. Keep this item or undo an earlier decision.")
                return false
            }
        }
        isSaving = true
        defer { isSaving = false }
        do {
            if let destination { try await access.grant(destination) }
            draft.decisions.append(ReviewDecision(item: item, choice: choice, destination: destination))
            try await store.saveCleanupState(Optional(draft), key: "draft")
            session = draft
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func discardSession() async {
        guard !isBusy, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.saveCleanupState(Optional<ReviewSession>.none, key: "draft")
            session = nil
        } catch { self.error = error.localizedDescription }
    }

    func undoDecision() async {
        guard var draft = session, !draft.decisions.isEmpty, draft.applicationStartedAt == nil,
            !isBusy, !isSaving
        else { return }
        isSaving = true
        defer { isSaving = false }
        draft.decisions.removeLast()
        do {
            try await store.saveCleanupState(Optional(draft), key: "draft")
            session = draft
        } catch { self.error = error.localizedDescription }
    }

    func commitSession() async {
        guard var draft = session, draft.current == nil, !isBusy, !isSaving else { return }
        isSaving = true
        draft.applicationStartedAt = draft.applicationStartedAt ?? Date()
        do {
            try await store.saveCleanupState(Optional(draft), key: "draft")
            session = draft
        } catch {
            isSaving = false
            self.error = error.localizedDescription
            return
        }
        isSaving = false
        execute(draft.pendingChanges, tool: draft.tool, batchID: draft.id) { [weak self] in
            guard let self else { return }
            var history =
                try await store.loadCleanupState([String: ReviewChoice].self, key: "review:" + draft.scopeID) ?? [:]
            for decision in draft.decisions where decision.choice == .keep { history[decision.item.reviewKey] = .keep }
            for event in sessionResults where event.state == .complete {
                history[event.item.reviewKey] = event.action == "move" ? .move : .trash
            }
            try await store.saveCleanupState(history, key: "review:" + draft.scopeID)
            if scope.id == draft.scopeID { reviewed = history }
            completedSession = draft
            try await store.saveCleanupState(Optional<ReviewSession>.none, key: "draft")
            session = nil
        }
    }

    func trashSelection(_ batch: CleanupBatch) {
        guard !batch.tool.isCompression, validate(batch) else { return }
        let decisions = batch.items.map {
            ReviewDecision(item: $0, choice: .trash)
        }
        execute(decisions, tool: batch.tool, batchID: batch.id.uuidString) {}
    }

    private func execute(
        _ decisions: [ReviewDecision], tool: CleanupTool, batchID: String,
        completion: @escaping @MainActor () async throws -> Void
    ) {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        notice = nil
        sessionResults = []
        task = Task {
            defer {
                isBusy = false
                task = nil
            }
            do {
                for (index, decision) in decisions.enumerated() {
                    try Task.checkCancellation()
                    progress = CleanupProgress(
                        String(localized: "Applying approved changes"), completed: index, total: decisions.count)
                    let event = await executor.apply(
                        decision, tool: tool, operationID: batchID + "|" + decision.item.id)
                    sessionResults.append(event)
                }
                try Task.checkCancellation()
                if sessionResults.allSatisfy({ $0.state == .complete }) {
                    let trashed = sessionResults.filter { $0.action == "trash" }
                    if !trashed.isEmpty {
                        notice = String(
                            localized: """
                                \(trashed.count) items · \(trashed.reduce(0) { $0 + $1.bytes }.formattedByteCount) \
                                removed. Files are in Trash; Photos assets are in Recently Deleted. \
                                Empty them in Finder or Photos to return space.
                                """
                        )
                    }
                    try await completion()
                } else {
                    error = String(localized: "Some changes did not complete. Check each result in Activity.")
                }
            } catch is CancellationError {
                error = String(
                    localized: "Cancelled. Completed changes remain in Activity; remaining items were not changed.")
            } catch { self.error = error.localizedDescription }
            await mutationFinished()
        }
    }

    func compressSelection(_ batch: CleanupBatch) {
        guard !isBusy, batch.tool.isCompression, validate(batch) else { return }
        let selected = batch.items
        let settings = batch.settings
        progress = CleanupProgress(String(localized: "Compressing media"), completed: 0, total: selected.count)
        jobs = selected.map {
            CompressionJob(item: $0, estimatedBytes: MediaCompressionService.estimate($0, settings: settings))
        }
        isBusy = true
        notice = nil
        error = nil
        task = Task {
            defer {
                isBusy = false
                task = nil
            }
            await withTaskGroup(of: (Int, ActivityEvent).self) { group in
                var next = 0
                func add(_ index: Int) {
                    let item = selected[index]
                    group.addTask { [executor] in
                        let event = await executor.compress(item, settings: settings) { [self] fraction in
                            await MainActor.run { self.jobs[index].progress = fraction }
                        }
                        return (index, event)
                    }
                }
                while next < min(2, selected.count) {
                    add(next)
                    next += 1
                }
                while let (index, event) = await group.next() {
                    jobs[index].event = event
                    progress.completed += 1
                    if next < selected.count, !Task.isCancelled {
                        add(next)
                        next += 1
                    }
                }
            }
            let successful = jobs.filter { $0.event?.state == .complete }.count
            let unprocessed = jobs.filter { $0.event == nil }.count
            let failed = jobs.count - successful - unprocessed
            if failed > 0 || unprocessed > 0 {
                error = String(
                    localized:
                        "\(successful) successful · \(failed) failed · \(unprocessed) unprocessed. Check Activity.")
            }
            await mutationFinished()
        }
    }

    func keepResource(_ item: ReviewItem, index: Int) {
        guard !isBusy, result?.isFresh == true, result?.scopeID == scope.id else { return }
        isBusy = true
        notice = nil
        error = nil
        task = Task {
            defer {
                isBusy = false
                task = nil
            }
            let event = await executor.keepPhotoResource(item, index: index)
            if let error = event.error { self.error = error }
            await mutationFinished()
        }
    }

    func restore(_ event: ActivityEvent) async {
        guard !isBusy, !isSaving else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await executor.restore(event)
            await mutationFinished()
        } catch { self.error = error.localizedDescription }
    }

    func resetHistory() async {
        guard !isBusy, !isSaving else { return }
        do {
            try await store.resetReviewHistory()
            reviewed = [:]
            session = nil
            completedSession = nil
            sessionResults = []
        } catch { self.error = error.localizedDescription }
    }

    func localURL(_ item: ReviewItem) async throws -> URL {
        guard !item.isLink, item.isDownloaded else {
            throw CleanupError.message(
                String(localized: "Links and files that are not downloaded have no content preview."))
        }
        if let url = item.url { return url }
        return try await photos.previewURL(for: item)
    }

    private func mutationFinished() async {
        result?.isFresh = false
        selection = []
        do { try await reloadHistory() } catch { self.error = error.localizedDescription }
    }

    private func reloadHistory() async throws {
        activity = try await store.cleanupActivity()
        snapshots = try await store.cleanupSnapshots(scopeID: scope.id)
    }

    private func startMonitoring() {
        freshness = CleanupFreshnessMonitor(roots: scope.roots, includesPhotos: scope.includesPhotos) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.changeGeneration += 1
                self.result?.isFresh = false
                if !self.isBusy, self.session == nil { self.scan() }
            }
        }
    }

    private func updateReminder() async throws {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["cleanup-weekly"])
        guard settings.reminderEnabled, let result else { return }
        guard try await center.requestAuthorization(options: [.alert, .sound]) else {
            throw CleanupError.message(String(localized: "Notifications are disabled in System Settings."))
        }
        let items = MediaAnalysisService.candidates(.screenshots, in: result)
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Weekly cleanup")
        content.body = String(
            localized: """
                Last scan \(result.completedAt.formatted(date: .abbreviated, time: .omitted)): \
                \(items.count) screenshots (\(items.reduce(0) { $0 + $1.bytes }.formattedByteCount)) \
                to review.
                """
        )
        content.userInfo = ["route": "cleanup"]
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(
                hour: 9, minute: 0,
                weekday: settings.reminderWeekday), repeats: true)
        try await center.add(UNNotificationRequest(identifier: "cleanup-weekly", content: content, trigger: trigger))
    }
}
