import AppKit
import Foundation
import MacOSCleanerCore
import Observation
import os
import SwiftUI

/// Persisted UserDefaults keys. Single source of truth: saveSettings,
/// loadSettings, and clearAllData all derive their key lists from this enum,
/// so adding a setting automatically extends the clear-all behavior.
private enum SettingsKey: String, CaseIterable {
    case selectedMode
    case selectedFolderPaths
    case cleanupPosture
    case includeAI
    case providerName
    case apiBaseURL
    case textModel
    case maxTokens
    case temperature
    case privacyMode
    case exploreViewKind
    case exploreGrouping
    case exploreDepth
    case duplicateStrategy
    case autoscanEnabled
    case inboxRootPath
}

@MainActor
@Observable
final class AppViewModel {
    var selectedMode: ScanMode = .selectedFolders
    var selectedFolders: [URL] = []
    var cleanupPosture: CleanupPosture = .conservative
    /// How exact duplicate groups are resolved by default. APFS clone folding
    /// is the default because it reclaims space without deleting anything.
    var duplicateStrategy: DuplicateStrategy = .apfsClone
    /// Unattended daily maintenance: installs the LaunchAgent, and the headless
    /// run folds duplicate files only — it can never delete anything.
    var autoscanEnabled = false {
        didSet {
            guard !suppressAutoscanObserver else { return }
            guard oldValue != autoscanEnabled else { return }
            if autoscanEnabled {
                do {
                    try LaunchAgentInstaller.install()
                } catch {
                    // Roll the toggle back WITHOUT re-entering this observer:
                    // a failed install (dev build outside /Applications) must
                    // never delete a LaunchAgent belonging to an installed
                    // copy of the app.
                    suppressAutoscanObserver = true
                    autoscanEnabled = false
                    suppressAutoscanObserver = false
                    errorMessage = error.localizedDescription
                }
            } else {
                LaunchAgentInstaller.remove()
            }
        }
    }
    /// Set while rolling back `autoscanEnabled` so the observer does not fire.
    private var suppressAutoscanObserver = false
    /// When the headless `--autoscan` last completed a run (nil = never).
    var lastAutoScanDate: Date? {
        UserDefaults.standard.object(forKey: AutoScanRunner.lastRunKey) as? Date
    }
    var providerSettings = ProviderSettings()
    var includeAI = false
    var apiKeyInput = ""
    private(set) var isScanning = false
    private(set) var isExecuting = false
    private(set) var isPlanning = false

    /// Claims the planning slot for a staging or NL-planning operation.
    /// Returns false when a scan, execution, or other planning is in flight,
    /// so callers can surface a "busy" message instead of a silent no-op.
    func claimPlanning() -> Bool {
        guard !isScanning, !isExecuting, !isPlanning else { return false }
        isPlanning = true
        return true
    }

    func releasePlanning() {
        isPlanning = false
    }
    /// Monotonic counter distinguishing the newest scan task from cancelled
    /// predecessors still unwinding; guards busy-state ownership.
    private(set) var scanGeneration = 0
    // Internal setters (not `private(set)`) so the AppViewModel+Tabs and
    // AppViewModel+Explore extensions (separate files) can update state.
    // All mutation still funnels through @MainActor methods.
    var statusMessage = String(localized: "Choose folders or a scan mode to begin.")
    var errorMessage: String?
    var showOnboarding = true
    var outcome: ScanOutcome? {
        didSet {
            _cachedFilesByID = nil
            _cachedSubtreeTotals = nil
        }
    }
    /// Mutable plan stored separately from the immutable scan outcome.
    /// This avoids copying the entire file array on every plan mutation.
    var plan: Plan?
    var selectedActionID: String?
    var reviewRiskFilter: RiskLevel?
    var naturalLanguageCommand = ""
    private(set) var executionSummary: ExecutionSummary?
    private(set) var lastExecutionActionIDs: Set<String> = []
    private(set) var executionProgress: Double = 0
    private(set) var executionTotalActions: Int = 0
    private(set) var executionCompletedActions: Int = 0
    private(set) var scanCurrentStep: Int = 0
    private(set) var scanTotalSteps: Int = 0
    private(set) var scanPhaseText = ""
    private(set) var generatedReportURL: URL?
    private(set) var showScanSummaryToast = false
    private(set) var activeScanSummary: String?
    private(set) var undoRecords: [UndoRecord] = []
    private(set) var historyActions: [PlannedAction] = []
    private(set) var isUsingTempDatabase = false
    /// Non-nil when a completed broad scan returned suspiciously few files —
    /// likely truncated by missing Full Disk Access. Shown as a dismissible banner.
    private(set) var fullDiskAccessHint: String?
    var selectedRegretReason: String?
    private(set) var spaceForecast: SpaceForecaster.Forecast?
    // MARK: - Top-level tabs (Agent 6; state lives here, behavior in AppViewModel+Tabs.swift)

    /// Selected top-level tab. Explore is the existing scan/review workspace;
    /// the other tabs are read-first surfaces that reuse scan results.
    var destination: AppDestination = .overview
    var settingsSection = SettingsSection.general
    var selectedApplicationID: String?
    var selectedHistoryID: String?
    var selectedSnapshotID: String?
    var searchText = ""
    var showsScanSetup = false
    var showsPlanner = false
    var showsInspector = false
    var searchFocusRequest = 0
    /// Which half of the Explore workspace is visible. Splits the previous
    /// mega-scroll (Dashboard + review queue on one page) into two focused
    /// pages: Dashboard for metrics, Review for the approval queue.
    /// Installed applications enumerated by ApplicationFootprintService.
    /// Loaded lazily when the Applications tab appears.
    var installedApplications: [InstalledApplication] = []
    var isLoadingApplications = false
    /// Per-app footprint items, keyed by application id. Loaded on demand per
    /// expanded row so enumerating every Library location for every app is
    /// never done up front.
    var footprintItemsByAppID: [String: [ApplicationFootprintItem]] = [:]
    var stagedUninstallAppIDs: Set<String> = []
    /// Apps that left /Applications while Tidybyte ran, by bundle ID.
    var removedApplications: [String: InstalledApplication] = [:]
    @ObservationIgnored var removalWatcher: ApplicationRemovalWatcher?
    // MARK: - Explore visualizations (Agent 4; persisted via SettingsKey)

    /// Selected Explore visualization tab. Stored as a raw string so the view
    /// layer's `ExploreViewKind` (a UI enum) never leaks into the model.
    var exploreViewKindRaw: String = "list"
    /// Selected Explore grouping dimension ("byFolder" | "byType" | "byAge").
    var exploreGroupingRaw: String = "byFolder"
    /// Selected Explore folder depth (1...10). Clamped on load.
    var exploreDepth: Int = 7
    /// FileRecord id currently selected in an Explore visualization.
    /// Transient UI state: resolved against `filesByID`, never persisted.
    var selectedExploreRecordID: String?
    /// FileRecord id the Explore list is drilled into ("focused").
    /// Transient UI state, never persisted.
    var focusedExploreRecordID: String?

    /// Snapshot history for the Snapshots tab and Monitor growth surface.
    var storageSnapshots: [StorageSnapshot] = []
    var isLoadingSnapshots = false
    /// Snapshot IDs picked in the Snapshots tab pickers.
    var olderSnapshotID: String?
    var newerSnapshotID: String?
    var snapshotDiff: SnapshotDiff?
    var snapshotDiffError: String?

    /// Top-level navigation tabs. Order matches the tab bar.
    enum RegretReason: String, CaseIterable {
        case neededLater = "Needed later"
        case misclassified = "Misclassified"
        case shouldHaveArchived = "Should have archived, not deleted"
        case wrongProject = "Wrong project"
        case tooAggressive = "Too aggressive"
    }

    struct ScanSummary: Equatable {
        let duration: TimeInterval
        let totalCandidates: Int
        let reviewableActions: Int
        let highRiskActions: Int
    }

    private var _cachedFilesByID: [String: FileRecord]?
    private var _cachedSubtreeTotals: [String: Int64]?
    private var scanTask: Task<Void, Never>?
    private var scanToastTask: Task<Void, Never>?
    private var activeScanID = UUID()
    let cleanup: CleanupModel
    internal let store: SQLiteStore
    private let keychain: KeychainStore
    private let memory: MemoryEngine
    private let orchestrator: ScanOrchestrator
    private let executor: ActionExecutor
    private let undoService: UndoManagerService
    private let reportGenerator: ReportGenerator
    let notifications: NotificationScheduler
    internal let planner: PlannerAgent
    private let inboxManager: InboxManager
    private let inboxRoot: URL?
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "AppViewModel")

    init(
        store: SQLiteStore,
        keychain: KeychainStore,
        memory: MemoryEngine,
        orchestrator: ScanOrchestrator,
        executor: ActionExecutor,
        undoService: UndoManagerService,
        reportGenerator: ReportGenerator,
        notifications: NotificationScheduler,
        planner: PlannerAgent,
        inboxManager: InboxManager = InboxManager(),
        defaults: UserDefaults = .standard,
        inboxRoot: URL? = nil
    ) {
        self.store = store
        self.cleanup = CleanupModel(store: store)
        self.keychain = keychain
        self.memory = memory
        self.orchestrator = orchestrator
        self.executor = executor
        self.undoService = undoService
        self.reportGenerator = reportGenerator
        self.notifications = notifications
        self.planner = planner
        self.inboxManager = inboxManager
        self.inboxRoot = inboxRoot
        self.defaults = defaults
        loadSettings()
        sweepInterruptedOperations()
    }

    /// Startup sweep for interrupted operations: a crash between the filesystem
    /// mutation and the finalize write leaves PENDING undo records behind. After
    /// a grace window (in-flight executions from a concurrent launch), surface
    /// them so the user knows files may be sitting in the Trash with a trail.
    private func sweepInterruptedOperations() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let graceCutoff = Date().addingTimeInterval(-300)
            do {
                let stale = try await store.loadStalePendingUndos(olderThan: graceCutoff)
                guard !stale.isEmpty else { return }
                let paths = stale.compactMap { $0.log?.beforeState["path"] }
                var message = String(
                    localized: "A previous cleanup was interrupted; \(stale.count) operation(s) may be incomplete.",
                    comment: "Startup sweep warning header"
                )
                if !paths.isEmpty {
                    let preview = paths.prefix(3).joined(separator: ", ")
                    message += " " + String(
                        localized: "Affected: \(preview)\(paths.count > 3 ? "…" : ""). Check the Trash and undo history.",
                        comment: "Startup sweep affected-paths suffix"
                    )
                }
                logger.warning("Interrupted operations found at startup: \(paths.joined(separator: ", "), privacy: .public)")
                errorMessage = message
            } catch {
                logger.warning("Startup sweep failed: \(error.localizedDescription)")
            }
        }
    }

    static func bootstrap() -> AppViewModel {
        do {
            let store = try SQLiteStore()
            let keychain = KeychainStore()
            let memory = MemoryEngine(store: store)
            let planner = PlannerAgent()
            let orchestrator = ScanOrchestrator(
                store: store,
                planner: planner,
                memory: memory
            )
            let executor = ActionExecutor(store: store)
            let undo = UndoManagerService(store: store, memory: memory)
            let reports = ReportGenerator(store: store)
            return AppViewModel(
                store: store,
                keychain: keychain,
                memory: memory,
                orchestrator: orchestrator,
                executor: executor,
                undoService: undo,
                reportGenerator: reports,
                notifications: NotificationScheduler(),
                planner: planner
            )
        } catch {
            let fallbackURL = FileManager.default.temporaryDirectory.appendingPathComponent("MacOSCleaner.sqlite", isDirectory: false)
            let store = (try? SQLiteStore(databaseURL: fallbackURL)) ?? tryFallbackStore()
            let keychain = KeychainStore()
            let memory = MemoryEngine(store: store)
            let planner = PlannerAgent()
            let model = AppViewModel(
                store: store,
                keychain: keychain,
                memory: memory,
                orchestrator: ScanOrchestrator(store: store, planner: planner, memory: memory),
                executor: ActionExecutor(store: store),
                undoService: UndoManagerService(store: store, memory: memory),
                reportGenerator: ReportGenerator(store: store),
                notifications: NotificationScheduler(),
                planner: planner
            )
            model.isUsingTempDatabase = true
            model.errorMessage = String(localized: "Primary database failed. Using a temporary database. Data will not persist after quit.")
            return model
        }
    }

    /// O(n·depth) subtree byte totals, computed once per scan. The Explore
    /// inspector previously recomputed these on every render.
    var subtreeTotals: [String: Int64] {
        if let cached = _cachedSubtreeTotals {
            return cached
        }
        guard let outcome else {
            return [:]
        }
        let totals = ExploreSubtreeIndex.totals(files: outcome.files)
        _cachedSubtreeTotals = totals
        return totals
    }

    var filesByID: [String: FileRecord] {
        if let cached = _cachedFilesByID {
            return cached
        }
        guard let outcome else {
            return [:]
        }
        let dict = Dictionary(outcome.files.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        _cachedFilesByID = dict
        return dict
    }

    var selectedAction: PlannedAction? {
        guard let selectedActionID, let plan else {
            return nil
        }
        return plan.actions.first { $0.id == selectedActionID }
    }

    var selectedActionFiles: [FileRecord] {
        guard let selectedAction else {
            return []
        }
        return selectedAction.targets.compactMap { filesByID[$0] }
    }

    var dashboardSections: [(FindingCategory, Int64)] {
        guard let outcome else {
            return []
        }
        return Dictionary(grouping: outcome.findings, by: \.category)
            .mapValues { $0.reduce(Int64(0)) { $0 + $1.bytesReclaimable } }
            .sorted { $0.value > $1.value }
    }

    func addDownloadFolderToSelection() {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            errorMessage = String(localized: "Could not resolve Downloads folder.")
            return
        }
        addScanFolder(downloads)
    }

    func addHomeFolderToSelection() {
        addScanFolder(FileManager.default.homeDirectoryForCurrentUser)
    }

    func addScanFolder(_ folder: URL) {
        guard !isScanning, !isExecuting else {
            errorMessage = String(localized: "Wait until scan or execution completes to change scan folders.")
            return
        }
        let normalized = folder.standardizedFileURL
        guard FileManager.default.fileExists(atPath: normalized.path) else {
            errorMessage = String(localized: "The selected folder no longer exists.")
            return
        }
        selectedFolders = mergeSelectedFolders(with: [normalized])
        selectedMode = .selectedFolders
        showOnboarding = false
        saveSettings()
        let count = selectedFolders.count
        statusMessage = count == 1
            ? String(localized: "1 folder selected. Ready to scan.", comment: "Status after adding a scan folder")
            : String(localized: "\(count) folders selected. Ready to scan.", comment: "Status after adding a scan folder")
    }

    func removeSelectedFolder(_ folder: URL) {
        guard !isScanning, !isExecuting else {
            errorMessage = String(localized: "Wait until scan or execution completes to change scan folders.")
            return
        }

        let normalized = folder.standardizedFileURL
        let existingCount = selectedFolders.count
        selectedFolders.removeAll { $0.standardizedFileURL == normalized }
        guard selectedFolders.count != existingCount else { return }
        saveSettings()

        if selectedFolders.isEmpty {
            statusMessage = String(localized: "No folders selected.")
            showOnboarding = selectedMode == .selectedFolders
        } else if selectedFolders.count == 1 {
            statusMessage = String(localized: "1 folder remains selected.")
        } else {
            statusMessage = String(localized: "\(selectedFolders.count) folders remain selected.")
        }
    }

    func clearSelectedFolders() {
        guard !isScanning, !isExecuting else {
            errorMessage = String(localized: "Wait until scan or execution completes to change scan folders.")
            return
        }
        guard !selectedFolders.isEmpty else {
            statusMessage = String(localized: "No folders selected.")
            return
        }
        selectedFolders.removeAll()
        saveSettings()
        statusMessage = String(localized: "All scan folders removed.")
        showOnboarding = selectedMode == .selectedFolders
    }

    func openLatestReport() {
        guard let reportURL = generatedReportURL else {
            errorMessage = String(localized: "No report generated yet.")
            return
        }
        NSWorkspace.shared.open(reportURL)
        statusMessage = String(localized: "Opened last report.")
    }

    func createInbox() async {
        guard !isScanning, !isExecuting else { return }
        let root: URL?
        if let inboxRoot {
            root = inboxRoot
        } else if !DistributionChannel.supportsAdvanced {
            // The App Store sandbox denies creating folders at arbitrary home
            // paths, so the user picks (and we remember) the parent folder.
            guard let picked = pickInboxParentFolder() else {
                statusMessage = String(localized: "Inbox creation canceled.")
                return
            }
            root = picked
        } else {
            root = nil
        }
        do {
            let inbox = try await inboxManager.ensureInboxExists(at: root)
            if !selectedFolders.contains(inbox) {
                selectedFolders.append(inbox)
            }
            selectedMode = .selectedFolders
            showOnboarding = false
            statusMessage = String(localized: "Tidybyte Inbox is ready.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Returns the folder the sandboxed build should create the inbox in:
    /// the previously chosen location if there is one, otherwise an
    /// NSOpenPanel selection that is persisted for later launches.
    private func pickInboxParentFolder() -> URL? {
        if let stored = defaults.string(forKey: SettingsKey.inboxRootPath.rawValue) {
            return URL(fileURLWithPath: stored)
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = String(
            localized: "Choose where Tidybyte should create the inbox folder.",
            comment: "Inbox creation folder picker message")
        panel.prompt = String(localized: "Create Here", comment: "Inbox creation folder picker button")
        guard panel.runModal() == .OK, let parent = panel.url else { return nil }
        defaults.set(parent.path, forKey: SettingsKey.inboxRootPath.rawValue)
        return parent
    }

    func saveAPIKey() async {
        guard !isScanning, !isExecuting else { return }
        do {
            // Key the keychain entry by provider so switching providers keeps
            // per-provider keys separate.
            try await keychain.saveAPIKey(apiKeyInput, account: providerSettings.providerName)
            apiKeyInput = ""
            // Never silently override the user's chosen privacy mode when a key is saved.
            // A key alone does not opt the user into content-based analysis; the status
            // message surfaces the current mode so they can change it explicitly.
            if !includeAI {
                includeAI = true
            }
            if providerSettings.privacyMode == .localOnly {
                statusMessage = String(localized: "API key saved. AI is on, but privacy mode is still Local Only; choose a mode with AI to use scanned content.")
            } else {
                statusMessage = String(localized: "API key saved in Keychain.")
            }
            saveSettings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func runScan(postureOverride: CleanupPosture? = nil) {
        guard !isScanning, !isExecuting, !isPlanning else { return }
        guard !selectedFolders.isEmpty || selectedMode != .selectedFolders else {
            errorMessage = String(localized: "Please select folders to scan.", comment: "Error when no folders selected")
            return
        }
        let scanID = UUID()
        activeScanID = scanID
        scanTask?.cancel()
        // Bump the generation so an unwinding older task knows it no longer
        // owns the busy-state flags.
        scanGeneration += 1
        let generation = scanGeneration
        // Flip busy-state SYNCHRONOUSLY (this method is MainActor-isolated): a
        // second runScan() arriving before the task starts must hit the guard,
        // and observers see the scanning state immediately.
        isScanning = true
        resetExecutionState()
        errorMessage = nil
        clearScanProgress()
        scanCurrentStep = 1
        scanPhaseText = String(localized: "Resolving scan scope")
        activeScanSummary = nil
        showScanSummaryToast = false
        let postureToUse = postureOverride ?? cleanupPosture
        statusMessage = String(localized: "Scan \(scanCurrentStep)/\(scanTotalSteps): \(scanPhaseText).")
        scanTask = Task { @MainActor in
            let startedAt = Date()
            // Every exit path clears the busy flag when this task actually
            // unwinds (cancellation included) — as long as no newer scan took
            // ownership in the meantime.
            defer {
                if generation == scanGeneration {
                    isScanning = false
                    if Task.isCancelled { statusMessage = String(localized: "Scan cancelled.") }
                }
            }
            do {
                let progressSink = makeScanProgressSink(for: scanID)
                let (scanOutcome, scanPlan) = try await orchestrator.scan(
                    mode: selectedMode,
                    selectedFolders: selectedFolders,
                    providerSettings: providerSettings,
                    includeAI: includeAI,
                    posture: postureToUse,
                    duplicateStrategy: duplicateStrategy,
                    progress: progressSink
                )
                guard !Task.isCancelled else {
                    // Only a cancelled scan may report the cancellation; a stale cancelled
                    // task must not repaint a newer scan's state (H-01).
                    guard activeScanID == scanID else { return }
                    statusMessage = String(localized: "Scan cancelled.")
                    return
                }
                outcome = scanOutcome
                plan = scanPlan
                reviewRiskFilter = nil
                stagedUninstallAppIDs = []
                selectedActionID = scanPlan.actions.first?.id
                showOnboarding = false
                clearScanProgress()
                evaluateFullDiskAccessHint(scanOutcome: scanOutcome, mode: selectedMode)
                let duration = Date().timeIntervalSince(startedAt)
                let summary = ScanSummary(
                    duration: duration,
                    totalCandidates: scanPlan.actions.count,
                    reviewableActions: scanPlan.actions.count,
                    highRiskActions: scanPlan.actions.filter { action in
                        action.risk == .high || action.risk == .forbidden
                    }.count
                )
                showScanSummaryToast = true
                activeScanSummary = formattedScanSummary(summary)
                statusMessage = String(localized: "Scan complete. Review every action before execution.")
                await notifications.scheduleScanCompletedNotification(reclaimedBytes: scanPlan.estimatedReclaimableBytes)
                // Schedule weekly digest if not already scheduled
                await notifications.scheduleWeeklyGrowthDigest()
                // Load storage timeline for forecasting
                await loadStorageTimeline()
                scanToastTask?.cancel()
                scanToastTask = Task { @MainActor in
                    do {
                        try await Task.sleep(nanoseconds: 6_000_000_000)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    showScanSummaryToast = false
                    activeScanSummary = nil
                }
            } catch {
                guard !Task.isCancelled else {
                    // See the success-path guard above: a stale cancelled task must not
                    // repaint a newer scan's state.
                    guard activeScanID == scanID else { return }
                    statusMessage = String(localized: "Scan cancelled.")
                    return
                }
                errorMessage = error.localizedDescription
                statusMessage = String(localized: "Scan failed.")
                // ON-11: keep the workspace when a scan already produced results; only
                // fall back to onboarding when there is genuinely nothing to show.
                if plan == nil && outcome == nil {
                    showOnboarding = true
                }
            }
        }
    }

    func runSaferScan() {
        let saferPosture: CleanupPosture = switch cleanupPosture {
        case .aggressive:
            .balanced
        case .balanced:
            .conservative
        case .conservative:
            .conservative
        }
        runScan(postureOverride: saferPosture)
    }

    func cancelScan() {
        // Nothing in flight: flipping the copy would strand "Cancelling…"
        // forever, since no task exists to unwind and clear it.
        guard isScanning else { return }
        scanTask?.cancel()
        scanTask = nil
        // Invalidate the current scan ID so a cancelled scan's stale progress sink or
        // cancellation message cannot repaint a newer scan's state.
        activeScanID = UUID()
        clearScanProgress()
        scanToastTask?.cancel()
        showScanSummaryToast = false
        activeScanSummary = nil
        statusMessage = String(localized: "Cancelling scan…")
        // Keep isScanning TRUE until the crawl actually unwinds at its next
        // cooperative checkpoint — the UI must not claim idle while disk work
        // continues. The task's epilogue clears isScanning when it really stops;
        // the guard above already prevents a cancelled task from repainting state.
    }

    /// Stop the in-flight batch after the current action completes. The action
    /// being written finishes (its undo trail stays consistent); the rest never run.
    func cancelExecution() {
        guard isExecuting else { return }
        Task {
            await executor.cancelExecution()
        }
        statusMessage = String(localized: "Cancelling execution after the current action…")
    }

    private func makeScanProgressSink(for scanID: UUID) -> @Sendable (ScanOrchestrator.ScanProgress) async -> Void {
        { [weak self] progress in
            guard let self else { return }
            await MainActor.run {
                guard self.activeScanID == scanID else { return }
                self.scanCurrentStep = progress.currentStep
                self.scanTotalSteps = progress.totalSteps
                self.scanPhaseText = progress.phase
                self.statusMessage = String(localized: "Scan \(progress.currentStep)/\(progress.totalSteps): \(progress.phase).")
            }
        }
    }

    private func clearScanProgress() {
        scanCurrentStep = 0
        scanTotalSteps = 5
        scanPhaseText = ""
    }

    private func formattedScanSummary(_ summary: ScanSummary) -> String {
        let durationText = formattedDuration(summary.duration)
        return String(
            localized: "What changed? \(durationText), \(summary.totalCandidates) candidates, \(summary.reviewableActions) reviewable actions, \(summary.highRiskActions) high-risk."
        )
    }

    /// Compact human-readable duration ("3s", "1m 12s"). Avoids
    /// DateComponentsFormatter's locale-dependent "0 secs" output in the
    /// scan-completion toast (G-04).
    private func formattedDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval.rounded())
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        }
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if seconds == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(seconds)s"
    }

    func approve(_ action: PlannedAction) {
        guard !isScanning, !isExecuting, !isPlanning else { return }
        updateAction(action.id) { item in
            item.userDecision = .approved
            item.status = .approved
            // An explicit approve gesture is the user's confirmation for high-risk
            // destructive work; SafetyAuditor requires this flag for risk >= .high.
            item.requiresExplicitConfirmation = true
        }
    }

    /// Swaps how one duplicate finding's pending actions resolve: fold the
    /// copies onto the keeper (APFS clone, nothing deleted) or move them to
    /// Trash. Only undecided actions are replaced — an approval or rejection
    /// is never silently reinterpreted. Persists the updated plan.
    func switchDuplicateResolution(forFinding findingID: String, to strategy: DuplicateStrategy) {
        guard var currentPlan = plan, !isScanning, !isExecuting, !isPlanning else { return }
        guard let finding = duplicateFindings.first(where: { $0.id == findingID }) else { return }
        let hasDecidedAction = currentPlan.actions.contains {
            $0.findingID == findingID && ($0.userDecision != .undecided || $0.executedAt != nil)
        }
        guard !hasDecidedAction else { return }
        currentPlan.actions.removeAll { $0.findingID == findingID }
        currentPlan.actions.append(contentsOf: PlannerAgent.duplicateResolutionActions(
            for: finding,
            filesByID: filesByID,
            strategy: strategy,
            planID: currentPlan.id
        ))
        currentPlan.actions.sort {
            $0.risk != $1.risk ? $0.risk < $1.risk : $0.confidence > $1.confidence
        }
        let targetIDs = Set(currentPlan.actions.flatMap(\.targets))
        currentPlan.estimatedReclaimableBytes = targetIDs.compactMap { filesByID[$0]?.sizeBytes }.reduce(Int64(0), +)
        currentPlan.estimatedFilesAffected = targetIDs.count
        currentPlan.riskBreakdown = Dictionary(grouping: currentPlan.actions, by: \.risk).mapValues(\.count)
        plan = currentPlan
        selectedActionID = currentPlan.actions.first { $0.findingID == findingID }?.id
        Task {
            try? await store.savePlan(currentPlan)
        }
    }

    func reject(_ action: PlannedAction) {
        guard !isScanning, !isExecuting, !isPlanning else { return }
        updateAction(action.id) { item in
            item.userDecision = .rejected
            item.status = .rejected
        }
    }

    func alwaysDoThis(_ action: PlannedAction) async {
        guard !isScanning, !isExecuting, !isPlanning else { return }
        updateAction(action.id) { item in
            item.userDecision = .alwaysDoThis
            item.status = .approved
            item.requiresExplicitConfirmation = true
        }
        if let updated = plan?.actions.first(where: { $0.id == action.id }) {
            do {
                try await memory.learn(from: updated, filesByID: filesByID)
            } catch {
                errorMessage = String(localized: "Could not save your preference: \(error.localizedDescription)")
            }
        }
    }

    func neverDoThisHere(_ action: PlannedAction) async {
        guard !isScanning, !isExecuting, !isPlanning else { return }
        updateAction(action.id) { item in
            item.userDecision = .neverDoThisHere
            item.status = .rejected
        }
        if let updated = plan?.actions.first(where: { $0.id == action.id }) {
            do {
                try await memory.learn(from: updated, filesByID: filesByID)
            } catch {
                errorMessage = String(localized: "Could not save your preference: \(error.localizedDescription)")
            }
        }
    }

    func executeApprovedActions() async {
        await executeApprovedActions(allowingRiskUpTo: .forbidden)
    }

    func executeConfirmedRequest(_ request: ExecutionRequest, packageCommandsOnly: Bool = false) async {
        guard request.isCurrent(in: self) else {
            errorMessage = String(localized: "The plan changed. Review the current actions and confirm again.")
            return
        }
        // Package-manager commands are non-undoable, so the UI confirms them
        // in a dedicated step, separate from file actions (AGENTS.md flow).
        let ids = packageCommandsOnly
            ? Set(request.actions.filter { $0.actionType == .runPackageManagerCleanup }.map(\.id))
            : request.actionIDs
        await executeApprovedActions(allowingRiskUpTo: request.maximumRisk, confirmedActionIDs: ids)
    }

    private func executeApprovedActions(
        allowingRiskUpTo maximumRisk: RiskLevel, confirmedActionIDs: Set<String>? = nil
    ) async {
        guard let outcome, let currentPlan = plan, !isScanning, !isExecuting, !isPlanning else {
            return
        }
        isExecuting = true
        let allApprovedActions = currentPlan.actions.filter {
            ($0.userDecision == .approved || $0.userDecision == .alwaysDoThis)
                && (confirmedActionIDs?.contains($0.id) ?? true)
        }
        let executableActionTypes: Set<ActionType> = [
            .moveToTrash, .move, .rename, .tag, .createAlias, .createSymlink,
            .archive, .runPackageManagerCleanup, .cloneDeduplicate
        ]
        let executableActions = allApprovedActions
            .filter { $0.risk <= maximumRisk }
            .filter { executableActionTypes.contains($0.actionType) }
        let reviewOnlyCount = allApprovedActions.filter { !executableActionTypes.contains($0.actionType) }.count
        guard !executableActions.isEmpty else {
            isExecuting = false
            if reviewOnlyCount > 0 {
                statusMessage = reviewOnlyCount == 1
                    ? String(localized: "1 approved action is review-only and was not executed.", comment: "Singular: one review-only action skipped")
                    : String(localized: "\(reviewOnlyCount) approved actions are review-only and were not executed.", comment: "Plural: multiple review-only actions skipped")
            } else {
                statusMessage = String(localized: "No approved actions in the selected risk band to execute.")
            }
            return
        }
        lastExecutionActionIDs = Set(executableActions.map(\.id))
        executionTotalActions = executableActions.count
        executionCompletedActions = 0
        executionProgress = 0
        statusMessage = String(
            localized: "Executing \(executionLabel(forRiskLimit: maximumRisk)) actions..."
        )
        plan?.status = .executing
        let candidates = outcome.packageCandidates
        let summary = await executor.execute(
            actions: executableActions,
            filesByID: filesByID,
            packageCandidates: candidates,
            progress: { [weak self] completed in
                await MainActor.run {
                    guard let self else { return }
                    self.executionCompletedActions = completed
                    self.executionProgress = Double(completed) / Double(max(1, self.executionTotalActions))
                }
            }
        )
        executionCompletedActions = executionTotalActions
        executionProgress = 1
        executionSummary = summary
        undoRecords = summary.undoRecords + undoRecords
        let completedIDs = Set(summary.logs.map(\.plannedActionID))
        let failedIDs = summary.failedActionIDs
        // Re-read self.plan in case it was mutated during execution (e.g., by NL command)
        var updatedPlan = self.plan ?? currentPlan
        let approvedActionIDs = Set(currentPlan.actions.filter {
            ($0.userDecision == .approved || $0.userDecision == .alwaysDoThis)
                && $0.executedAt == nil && $0.status != .completed && $0.status != .failed
        }.map(\.id))
        updatedPlan.actions = updatedPlan.actions.map { action in
            var changed = action
            if completedIDs.contains(action.id) || failedIDs.contains(action.id) {
                changed.status = failedIDs.contains(action.id) ? .failed : .completed
                changed.executedAt = Date()
            }
            return changed
        }
        let executedByID = Dictionary(
            updatedPlan.actions.filter { $0.executedAt != nil }.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest })
        updatedPlan.originalActions = updatedPlan.originalActions?.map { executedByID[$0.id] ?? $0 }
        let unresolvedActionIDs = approvedActionIDs.subtracting(completedIDs).subtracting(failedIDs)
        updatedPlan.status = unresolvedActionIDs.isEmpty && summary.failures.isEmpty
            ? .completed
            : .partiallyApproved
        self.plan = updatedPlan
        await saveExecutionHistory(updatedPlan)
        statusMessage = if summary.failures.isEmpty {
            if unresolvedActionIDs.isEmpty {
                String(localized: "All selected approved actions completed.")
            } else if maximumRisk == .low {
                String(localized: "Safe actions completed. Higher-risk approved actions are still pending.")
            } else {
                String(localized: "Execution completed with pending approved actions.")
            }
        } else {
            String(localized: "Some actions failed. Review the execution summary.")
        }
        // The auditor's `.needsManualReview` decision surfaces as a
        // manualReviewRequired failure; the user cannot resolve it in-place, so
        // guide them to refresh file identities with a new scan. Typed flag on
        // the summary — matching localized strings breaks in every other language.
        if summary.requiresRescan {
            errorMessage = String(localized: "Some actions need a fresh review: file identities changed since the scan. Run a new scan, then re-approve those actions.", comment: "Guidance when the safety auditor requires a re-scan")
        }
        isExecuting = false
        // Auto-learn patterns from this execution cycle
        do {
            try await memory.detectPatterns(from: currentPlan.actions, filesByID: filesByID)
        } catch {
            logger.warning("Pattern detection failed: \(error.localizedDescription)")
        }
    }

    func approvedActions(for maximumRisk: RiskLevel = .forbidden) -> [PlannedAction] {
        guard let currentPlan = plan else {
            return []
        }
        return currentPlan.actions.filter { action in
            (action.userDecision == .approved || action.userDecision == .alwaysDoThis) && action.risk <= maximumRisk
        }
    }

    func estimatedAffectedFileCount(for actions: [PlannedAction]) -> Int {
        actions.reduce(0) { total, action in
            total + action.targets.count
        }
    }

    func executionLabel(forRiskLimit maximumRisk: RiskLevel) -> String {
        switch maximumRisk {
        case .low:
            return String(localized: "low-risk")
        case .medium:
            return String(localized: "medium-risk and below")
        case .high:
            return String(localized: "high-risk and below")
        case .forbidden:
            return String(localized: "approved")
        }
    }

    func historyOperation(id: String) async -> OperationLog? {
        try? await store.loadOperationLog(id: id)
    }

    private func saveExecutionHistory(_ plan: Plan) async {
        let recordedActions = plan.actions.filter { $0.executedAt != nil }
        let recordedIDs = Set(recordedActions.map(\.id))
        historyActions = (recordedActions + historyActions.filter { !recordedIDs.contains($0.id) })
            .sorted { ($0.executedAt ?? .distantPast) > ($1.executedAt ?? .distantPast) }
        do {
            try await store.savePlan(plan)
        } catch {
            errorMessage = String(localized: "Could not save completed changes in History: \(error.localizedDescription)")
        }
    }

    func loadUndoHistory() async {
        do {
            // Purge expired undo records and orphaned operation logs before
            // loading, so the UI never shows stale entries.
            try await store.purgeOldData()
            undoRecords = try await store.loadUndoRecords()
            let plans = try await store.recentPlans(limit: Int.max)
            let recorded = plans.flatMap { ($0.originalActions ?? []) + $0.actions }
                .filter { $0.executedAt != nil }
            historyActions = Dictionary(recorded.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
                .values
                .sorted { ($0.executedAt ?? .distantPast) > ($1.executedAt ?? .distantPast) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadStorageTimeline() async {
        do {
            let forecaster = SpaceForecaster(store: store)
            // Use the home volume capacity as the disk capacity for forecasting.
            let homeURL = FileManager.default.homeDirectoryForCurrentUser
            if let capacity = SpaceForecaster.volumeCapacity(for: homeURL) {
                spaceForecast = try await forecaster.forecast(diskCapacity: capacity)
            }
            storageSnapshots = try await store.recentSnapshots(limit: 30)
            if olderSnapshotID == nil || newerSnapshotID == nil {
                olderSnapshotID = storageSnapshots.dropFirst().first?.id
                newerSnapshotID = storageSnapshots.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore(_ undo: UndoRecord) async {
        guard !isScanning, !isExecuting else { return }
        do {
            let restored = try await undoService.restore(undo)
            undoRecords = undoRecords.map { item in
                item.id == restored.id ? restored : item
            }
            statusMessage = String(localized: "Undo completed.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreWithReason(_ undo: UndoRecord) async {
        guard !isScanning, !isExecuting else { return }
        do {
            let restored = try await undoService.restore(undo, regretReason: selectedRegretReason)
            undoRecords = undoRecords.map { item in
                item.id == restored.id ? restored : item
            }
            selectedRegretReason = nil
            statusMessage = String(localized: "Undo completed.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func applyNaturalLanguageCommand() async -> Bool {
        guard !Task.isCancelled, let currentPlan = plan,
            !naturalLanguageCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        // Re-entrancy + race guards: no planning while a scan/execution runs,
        // and no overlapping NL commands (last-writer-wins clobbering).
        guard !isScanning, !isExecuting, !isPlanning else {
            statusMessage = String(localized: "Wait for the current operation to finish before running a command.")
            return false
        }
        isPlanning = true
        defer { isPlanning = false }
        let signature = executionPlanSignature
        let generation = scanGeneration
        let command = naturalLanguageCommand
        let updatedPlan = await planner.planForNaturalLanguageCommand(
            command,
            existingPlan: currentPlan,
            filesByID: filesByID
        )
        // Cancellation, a new scan (even if finished), or any changed decision
        // invalidates the result prepared from the old plan.
        guard !Task.isCancelled, !isScanning, !isExecuting,
            generation == scanGeneration, signature == executionPlanSignature else { return false }
        self.plan = updatedPlan
        selectedActionID = updatedPlan.actions.first?.id
        if updatedPlan.actions.isEmpty {
            statusMessage = String(localized: "No actions match '\(command)'. Try a different command or say 'everything' to restore.")
        } else if updatedPlan.actions.count == 1 {
            statusMessage = String(localized: "Command '\(command)' converted into 1 action.")
        } else {
            statusMessage = String(localized: "Command '\(command)' converted into \(updatedPlan.actions.count) actions.")
        }
        return true
    }

    /// Broad scan modes should see thousands of files on a normal Mac. A tiny
    /// result usually means Full Disk Access is missing and whole subtrees were
    /// silently skipped — surface the distinction instead of a false "clean".
    private func evaluateFullDiskAccessHint(scanOutcome: ScanOutcome, mode: ScanMode) {
        let broadModes: Set<ScanMode> = [.homeFolder, .developerCleanup]
        guard broadModes.contains(mode), !FullDiskAccess.isGranted() else {
            fullDiskAccessHint = nil
            return
        }
        fullDiskAccessHint = String(
            localized: "Tidybyte can't see Mail, Safari, and some app data. Turn on Full Disk Access to include them.",
            comment: "Full Disk Access suggestion banner"
        )
    }

    func dismissFullDiskAccessHint() {
        fullDiskAccessHint = nil
    }

    func generateReport(to directory: URL? = nil) async {
        guard let outcome, let currentPlan = plan else {
            statusMessage = String(localized: "Run a scan first to generate a report.")
            return
        }
        guard !isScanning, !isExecuting else { return }
        do {
            // The destination is injectable so callers (and tests) can direct the PDF
            // anywhere; the default keeps the historical ~/Tidybyte Reports location.
            let reportDirectory = directory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(AppIdentity.reportsFolderName, isDirectory: true)
            generatedReportURL = try await reportGenerator.generateCleanupReport(outcome: outcome, plan: currentPlan, destination: reportDirectory)
            statusMessage = String(localized: "Local PDF report generated.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyCalibrationPreset(_ preset: String) async {
        do {
            try await memory.applyCalibrationPreference(preset)
            statusMessage = String(localized: "Preference saved.", comment: "Calibration preset applied message")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setErrorMessage(_ message: String) {
        errorMessage = message
    }

    /// Status updates from surfaces outside the main UI flow (menu bar).
    func setStatusMessage(_ message: String) {
        statusMessage = message
    }

    func exportDatabase() async {
        guard !isScanning, !isExecuting else { return }
        do {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "MacOSCleaner-\(Date().formatted(date: .numeric, time: .omitted)).sqlite"
            panel.allowedContentTypes = [.data]
            guard let window = NSApp.mainWindow else { return }
            let response = await panel.beginSheetModal(for: window)
            guard response == .OK, let destination = panel.url else { return }
            guard !isScanning, !isExecuting else {
                errorMessage = String(localized: "Cannot export while a scan or execution is in progress.")
                return
            }
            // exportCopy checkpoints the WAL and runs a sqlite3 backup, so the exported
            // file contains committed WAL content that a plain FileManager copy would miss.
            try await store.exportCopy(to: destination)
            statusMessage = String(localized: "Database exported successfully.")
        } catch {
            errorMessage = String(localized: "Failed to export database: \(error.localizedDescription)")
        }
    }

    func clearAllData() async {
        guard !isScanning, !isExecuting else {
            errorMessage = String(localized: "Cannot clear data while a scan or execution is in progress.")
            return
        }
        do {
            try await keychain.deleteAllAPIKeys()
            try await store.deleteAllData()
            outcome = nil
            plan = nil
            undoRecords = []
            historyActions = []
            generatedReportURL = nil
            spaceForecast = nil
            naturalLanguageCommand = ""
            selectedFolders = []
            selectedMode = .selectedFolders
            cleanupPosture = .conservative
            includeAI = false
            providerSettings = ProviderSettings()
            // Must run before the defaults wipe below: the observer unregisters
            // the LaunchAgent, while removeObject alone leaves it installed.
            autoscanEnabled = false
            resetExecutionState()
            showOnboarding = true
            resetWorkspaceState()
            // Clear every persisted preference so loadSettings() cannot restore them
            // on the next launch and onboarding stays visible (ST-18). The key list
            // is derived from SettingsKey.allCases, so newly added settings are
            // cleared automatically.
            for key in SettingsKey.allCases {
                defaults.removeObject(forKey: key.rawValue)
            }
            statusMessage = String(localized: "All data cleared.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetWorkspaceState() {
        selectedActionID = nil
        reviewRiskFilter = nil
        destination = .overview
        searchText = ""
        selectedExploreRecordID = nil
        focusedExploreRecordID = nil
        selectedApplicationID = nil
        selectedHistoryID = nil
        selectedSnapshotID = nil
        showsInspector = false
        showsPlanner = false
        showsScanSetup = false
        exploreViewKindRaw = "list"
        exploreGroupingRaw = "byFolder"
        exploreDepth = 7
        storageSnapshots = []
        olderSnapshotID = nil
        newerSnapshotID = nil
        snapshotDiff = nil
        snapshotDiffError = nil
        footprintItemsByAppID = [:]
        stagedUninstallAppIDs = []
        fullDiskAccessHint = nil
    }

    private func resetExecutionState() {
        executionSummary = nil
        lastExecutionActionIDs = []
        executionProgress = 0
        executionTotalActions = 0
        executionCompletedActions = 0
        showScanSummaryToast = false
        activeScanSummary = nil
        // Cancel any lingering toast dismissal task so a stale timer from a
        // previous scan cannot prematurely clear the next scan's summary toast.
        scanToastTask?.cancel()
        scanToastTask = nil
    }

    private func updateAction(_ id: String, update: (inout PlannedAction) -> Void) {
        guard var currentPlan = plan else {
            return
        }
        currentPlan.actions = currentPlan.actions.map { action in
            guard action.id == id else {
                return action
            }
            var changed = action
            update(&changed)
            return changed
        }
        currentPlan.status = currentPlan.actions.contains(where: { $0.userDecision == .approved || $0.userDecision == .alwaysDoThis })
            ? .partiallyApproved
            : .proposed
        plan = currentPlan
        schedulePlanPersistence()
    }

    /// Cheap mutation counter for views: recomputing the plan's JSON signature
    /// several times per render re-encoded the whole plan on the main thread.
    private(set) var planRevision = 0

    private var planSaveTask: Task<Void, Never>?

    /// Debounced plan persistence: review decisions and staged actions must
    /// survive a crash or quit instead of living only in memory until
    /// execution. Rapid taps coalesce into one write after 500ms of quiet.
    func schedulePlanPersistence() {
        planRevision += 1
        guard let currentPlan = plan else { return }
        planSaveTask?.cancel()
        planSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            do {
                try await self?.store.savePlan(currentPlan)
            } catch {
                self?.logger.warning("Plan persistence failed: \(error.localizedDescription)")
            }
        }
    }

    private static func tryFallbackStore() -> SQLiteStore {
        let uniqueURL = FileManager.default.temporaryDirectory.appendingPathComponent("MacOSCleaner-\(UUID().uuidString).sqlite", isDirectory: false)
        if let store = try? SQLiteStore(databaseURL: uniqueURL) {
            return store
        }
        return (try? SQLiteStore.inMemory()) ?? SQLiteStore.unavailable
    }

    private func mergeSelectedFolders(with newFolders: [URL]) -> [URL] {
        var merged = selectedFolders
        for folder in newFolders {
            let normalized = folder.standardizedFileURL
            guard !merged.contains(where: { $0.standardizedFileURL == normalized }) else {
                continue
            }
            merged.append(normalized)
        }
        return merged
    }

    func saveSettings() {
        let defaults = self.defaults
        defaults.set(selectedMode.rawValue, forKey: SettingsKey.selectedMode.rawValue)
        defaults.set(selectedFolders.map(\.path), forKey: SettingsKey.selectedFolderPaths.rawValue)
        defaults.set(cleanupPosture.rawValue, forKey: SettingsKey.cleanupPosture.rawValue)
        defaults.set(duplicateStrategy.rawValue, forKey: SettingsKey.duplicateStrategy.rawValue)
        defaults.set(autoscanEnabled, forKey: SettingsKey.autoscanEnabled.rawValue)
        defaults.set(includeAI, forKey: SettingsKey.includeAI.rawValue)
        defaults.set(providerSettings.providerName, forKey: SettingsKey.providerName.rawValue)
        defaults.set(providerSettings.apiBaseURL.absoluteString, forKey: SettingsKey.apiBaseURL.rawValue)
        defaults.set(providerSettings.textModel, forKey: SettingsKey.textModel.rawValue)
        defaults.set(providerSettings.maxTokens, forKey: SettingsKey.maxTokens.rawValue)
        defaults.set(providerSettings.temperature, forKey: SettingsKey.temperature.rawValue)
        defaults.set(providerSettings.privacyMode.rawValue, forKey: SettingsKey.privacyMode.rawValue)
        defaults.set(exploreViewKindRaw, forKey: SettingsKey.exploreViewKind.rawValue)
        defaults.set(exploreGroupingRaw, forKey: SettingsKey.exploreGrouping.rawValue)
        defaults.set(exploreDepth, forKey: SettingsKey.exploreDepth.rawValue)
    }

    private func loadSettings() {
        let defaults = self.defaults
        if let modeRaw = defaults.string(forKey: SettingsKey.selectedMode.rawValue), let mode = ScanMode(rawValue: modeRaw) {
            selectedMode = mode
        }
        if let paths = defaults.stringArray(forKey: SettingsKey.selectedFolderPaths.rawValue) {
            selectedFolders = paths.map { URL(fileURLWithPath: $0) }
        }
        if let postureRaw = defaults.string(forKey: SettingsKey.cleanupPosture.rawValue), let posture = CleanupPosture(rawValue: postureRaw) {
            cleanupPosture = posture
        }
        if let strategyRaw = defaults.string(forKey: SettingsKey.duplicateStrategy.rawValue), let strategy = DuplicateStrategy(rawValue: strategyRaw) {
            duplicateStrategy = strategy
        }
        autoscanEnabled = defaults.bool(forKey: SettingsKey.autoscanEnabled.rawValue)
        includeAI = defaults.bool(forKey: SettingsKey.includeAI.rawValue)
        if let name = defaults.string(forKey: SettingsKey.providerName.rawValue) {
            providerSettings.providerName = name
        }
        if let urlString = defaults.string(forKey: SettingsKey.apiBaseURL.rawValue), let url = URL(string: urlString) {
            providerSettings.apiBaseURL = url
        }
        if let model = defaults.string(forKey: SettingsKey.textModel.rawValue) {
            providerSettings.textModel = model
        }
        if defaults.object(forKey: SettingsKey.maxTokens.rawValue) != nil {
            providerSettings.maxTokens = defaults.integer(forKey: SettingsKey.maxTokens.rawValue)
        }
        if defaults.object(forKey: SettingsKey.temperature.rawValue) != nil {
            providerSettings.temperature = defaults.double(forKey: SettingsKey.temperature.rawValue)
        }
        if let privacyRaw = defaults.string(forKey: SettingsKey.privacyMode.rawValue), let privacy = PrivacyMode(rawValue: privacyRaw) {
            providerSettings.privacyMode = privacy
        }
        if let viewKind = defaults.string(forKey: SettingsKey.exploreViewKind.rawValue), !viewKind.isEmpty {
            exploreViewKindRaw = viewKind
        }
        if let grouping = defaults.string(forKey: SettingsKey.exploreGrouping.rawValue), !grouping.isEmpty {
            exploreGroupingRaw = grouping
        }
        if defaults.object(forKey: SettingsKey.exploreDepth.rawValue) != nil {
            exploreDepth = max(1, min(10, defaults.integer(forKey: SettingsKey.exploreDepth.rawValue)))
        }
        if !selectedFolders.isEmpty {
            showOnboarding = false
        }
    }
}
