import Foundation
import os

public enum ScanOrchestratorError: Error, LocalizedError, Sendable {
    /// A scan mode is marked as a system-clean section but has no matching
    /// `MoCleanScanner.SystemCleanSection`. The two enums must stay in sync;
    /// failing loudly here beats silently producing an empty scan.
    case unsupportedSection(ScanMode)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSection(let mode):
            "Scan mode \(mode.rawValue) has no matching system-clean section. This is an internal configuration error; please reinstall the app."
        }
    }
}

public actor ScanOrchestrator {
    private let store: SQLiteStore
    private let permissionManager: PermissionManager
    private let crawler: FileCrawler
    private let projectDetector: ProjectDetector
    private let duplicateDetector: DuplicateDetector
    private let contentExtractor: ContentExtractor
    private let ruleEngine: CleanerRuleEngine
    private let organizationPlanner: OrganizationPlanner
    private let packageScanner: PackageManagerScanner
    private let moCleanScanner: MoCleanScanner
    private let planner: PlannerAgent
    private let aiGateway: AIGateway
    private let memory: MemoryEngine
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "ScanOrchestrator")

    public struct ScanProgress: Sendable {
        public let phase: String
        public let currentStep: Int
        public let totalSteps: Int
        /// Items the crawl has seen so far. Nil outside the crawl step.
        public let filesSeen: Int?
        /// The folder the crawl is currently inside. Nil outside the crawl step.
        public let currentPath: String?

        public init(
            phase: String, currentStep: Int, totalSteps: Int,
            filesSeen: Int? = nil, currentPath: String? = nil
        ) {
            self.phase = phase
            self.currentStep = currentStep
            self.totalSteps = max(1, totalSteps)
            self.filesSeen = filesSeen
            self.currentPath = currentPath
        }
    }

    public init(
        store: SQLiteStore,
        permissionManager: PermissionManager = PermissionManager(),
        crawler: FileCrawler = FileCrawler(),
        projectDetector: ProjectDetector = ProjectDetector(),
        duplicateDetector: DuplicateDetector? = nil,
        contentExtractor: ContentExtractor = ContentExtractor(),
        ruleEngine: CleanerRuleEngine = CleanerRuleEngine(),
        organizationPlanner: OrganizationPlanner = OrganizationPlanner(),
        packageScanner: PackageManagerScanner = PackageManagerScanner(),
        moCleanScanner: MoCleanScanner = MoCleanScanner(),
        planner: PlannerAgent = PlannerAgent(),
        aiGateway: AIGateway = AIGateway(),
        memory: MemoryEngine
    ) {
        self.store = store
        self.permissionManager = permissionManager
        self.crawler = crawler
        self.projectDetector = projectDetector
        // Default detector shares the store so duplicate hashing reuses the
        // persistent hash cache across scans.
        self.duplicateDetector = duplicateDetector ?? DuplicateDetector(hashCache: store)
        self.contentExtractor = contentExtractor
        self.ruleEngine = ruleEngine
        self.organizationPlanner = organizationPlanner
        self.packageScanner = packageScanner
        self.moCleanScanner = moCleanScanner
        self.planner = planner
        self.aiGateway = aiGateway
        self.memory = memory
    }

    /// The crawl step of the 5-step progress sequence, with the live item
    /// count and current folder folded in.
    private static func crawlProgressStep(
        _ crawl: FileCrawler.CrawlProgress, totalSteps: Int
    ) -> ScanProgress {
        ScanProgress(
            phase: String(localized: "Crawling files"),
            currentStep: 2,
            totalSteps: totalSteps,
            filesSeen: crawl.itemsSeen,
            currentPath: crawl.currentFolderName)
    }

    /// Scan state accumulated stage by stage. Declared outside the pipeline's
    /// do block so a cancellation can finalize what the scan found so far
    /// instead of discarding it — and because `~/Library`, the main source of
    /// findings, is crawled near the end, a discarded cancelled scan always
    /// looked like an empty Mac.
    private struct AccumulatedScan: Sendable {
        var files: [FileRecord] = []
        var errors = 0
        var projects: [ProjectUnit] = []
        var findings: [Finding] = []
        var recommendations: [Recommendation] = []
        var fingerprints: [FileFingerprint] = []
        var edges: [RelationshipEdge] = []
        var packageCandidates: [PackageCleanupCandidate] = []
        var contentSummaries: [ContentSummary] = []
        var notices: [ScanNotice] = []
        /// True once the rule engine has run, so the cancellation path does
        /// not run it a second time over the same files.
        var didRunRules = false
        /// True once `MemoryEngine.applyMemory` has run, so the cancellation
        /// path does not apply "never" / "always" rules twice.
        var didApplyMemory = false
    }

    /// Result of the rule pass a stopped scan runs over its partial files.
    /// A named struct keeps the tuple out of the detached closure's signature.
    private struct CancelledScanAnalysis: Sendable {
        let projects: [ProjectUnit]
        let findings: [Finding]
        let recommendations: [Recommendation]
    }

    public func scan(
        mode: ScanMode,
        selectedFolders: [URL],
        providerSettings: ProviderSettings,
        includeAI: Bool,
        posture: CleanupPosture = .conservative,
        duplicateStrategy: DuplicateStrategy = .apfsClone,
        progress: (@Sendable (ScanProgress) async -> Void)? = nil
    ) async throws -> (outcome: ScanOutcome, plan: Plan) {
        let totalSteps = 5
        let notifyProgress: @Sendable (Int, String) async -> Void = { step, phase in
            await progress?(.init(phase: phase, currentStep: step, totalSteps: totalSteps))
        }
        await notifyProgress(1, String(localized: "Resolving scan scope"))
        let roots = try await permissionManager.roots(for: mode, selectedFolders: selectedFolders)
        // Guard the section bridge BEFORE any persistence: a system-clean mode
        // without a matching section (enum drift) must fail loudly without
        // leaving a session stuck in .running forever.
        if mode.isSystemCleanSection, mode.systemCleanSection == nil {
            throw ScanOrchestratorError.unsupportedSection(mode)
        }
        let permissions = await permissionManager.permissionsSnapshot(for: roots, mode: mode)
        var session = ScanSession(scanType: mode, rootURLs: roots, permissionsSnapshot: permissions)
        try await store.saveScanSession(session)

        for volume in await permissionManager.mountedVolumes() {
            do {
                try await store.saveVolume(volume)
            } catch {
                logger.warning("Failed to save volume \(volume.volumeName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        var partial = AccumulatedScan()
        // Without Full Disk Access the crawler silently skips app containers.
        // When they sit under the scanned roots, say so — an app-data-shaped
        // hole in the results otherwise reads as a verified-clean Mac.
        let closedFolders = FullDiskAccess.closedAppDataFolders().filter {
            FileManager.default.fileExists(atPath: $0)
        }
        if !closedFolders.isEmpty,
            roots.contains(where: { root in
                closedFolders.contains { $0 == root.path || $0.hasPrefix(root.path + "/") }
            }) {
            partial.notices.append(ScanNotice(message: String(
                localized: "Some app data folders were skipped because Full Disk Access is off, so app caches and leftovers are missing from these results.",
                comment: "Scan notice when Full Disk Access is missing")))
        }

        // Stage durations go to the log so a slow scan can be attributed to a
        // stage after the fact instead of reported as one opaque number.
        let clock = ContinuousClock()
        var stageStart = clock.now
        func finishStage(_ name: String) {
            let elapsed = clock.now - stageStart
            logger.info("Scan \(session.id, privacy: .public) \(name, privacy: .public): \(String(describing: elapsed), privacy: .public)")
            stageStart = clock.now
        }

        // Package-manager probes run external commands with fixed timeouts
        // (brew's dry-runs alone can take ~16s) and do not depend on the
        // crawl, so they start here and overlap it. Declared outside the do
        // block so the catch paths can cancel a probe still in flight.
        let packageScanner = self.packageScanner
        let scanSessionID = session.id // Capture as a value: the session var is mutated below
        let packageTask: Task<([Finding], [Recommendation], [PackageCleanupCandidate]), Never>? =
            (mode == .developerCleanup || mode == .homeFolder)
            ? Task.detached { await packageScanner.scan(sessionID: scanSessionID) }
            : nil

        // Cooperative cancellation: each pipeline stage checks before doing heavy work so
        // cancelScan() stops the scan promptly instead of running every stage to completion.
        do {
            try Task.checkCancellation()

            // mo clean known-path sections take a separate, simpler pipeline:
            // crawl known paths → classify by section → memory/AI/planner/snapshot/store.
            if let section = mode.systemCleanSection {
                return try await scanSystemCleanSection(
                    section: section,
                    session: session,
                    roots: roots,
                    providerSettings: providerSettings,
                    includeAI: includeAI,
                    partial: &partial,
                    finishStage: finishStage,
                    notifyProgress: notifyProgress
                )
            }

            await notifyProgress(2, String(localized: "Crawling files"))
            // Relay the crawl's shared counter to the 5-step sink: the crawl is
            // the longest stage, so it reports what it is doing instead of a
            // bare "Crawling files" for minutes.
            let crawlSink: (@Sendable (FileCrawler.CrawlProgress) async -> Void)?
            if let progress {
                crawlSink = { crawl in
                    await progress(Self.crawlProgressStep(crawl, totalSteps: totalSteps))
                }
            } else {
                crawlSink = nil
            }
            let (files, errors) = await crawler.crawl(rootURLs: roots, sessionID: session.id, progress: crawlSink)
            finishStage("Crawl")
            partial.files = files
            partial.errors = errors
            if errors > 0 {
                let message = errors == 1
                    ? String(localized: "Crawl completed with 1 error across \(files.count) files.", comment: "Log: single crawl error")
                    : String(localized: "Crawl completed with \(errors) errors across \(files.count) files.", comment: "Log: multiple crawl errors")
                logger.warning("\(message, privacy: .public)")
                partial.notices.append(ScanNotice(message: String(
                    localized: "\(errors) items could not be read during the scan and are not included in these results.",
                    comment: "Scan notice for unreadable entries")))
            }
            await notifyProgress(3, String(localized: "Analyzing findings"))
            try Task.checkCancellation()

            // Pipeline: crawl first (needed by all subsequent stages), then parallelize independent stages.
            // Content extraction, duplicate detection, and project detection are independent of each other.
            let projects = try await projectDetector.detectProjects(in: files)
            partial.projects = projects
            let sessionID = session.id // Capture as local to avoid data race

            // Run duplicate detection in parallel with content extraction (they are independent).
            // PRIVACY: in localOnly mode no content extraction (OCR, PDF text, summaries) may
            // run or be persisted. Content summaries only exist when the privacy mode permits
            // reading file contents, so an empty array here means saveContentSummaries() below
            // persists nothing.
            async let duplicateTask = duplicateDetector.analyze(files: files, sessionID: sessionID, strategy: duplicateStrategy)
            let contentSummaries: [ContentSummary]
            if providerSettings.privacyMode == .localOnly {
                contentSummaries = []
            } else {
                contentSummaries = await contentExtractor.summarize(files: files, privacyMode: providerSettings.privacyMode)
            }
            let duplicateAnalysis = try await duplicateTask
            finishStage("Duplicates and content")
            partial.contentSummaries = contentSummaries
            partial.fingerprints = duplicateAnalysis.fingerprints
            partial.findings += duplicateAnalysis.findings
            partial.recommendations += duplicateAnalysis.recommendations
            partial.edges += duplicateAnalysis.edges
            try Task.checkCancellation()

            let projectEdges = await projectDetector.buildEdges(files: files, projects: projects)
            let (ruleFindings, ruleRecommendations) = try await ruleEngine.analyze(
                files: files, projects: projects, sessionID: sessionID, posture: posture)
            let (organizationFindings, organizationRecommendations) = try await organizationPlanner
                .suggestOrganization(files: files, sessionID: sessionID)
            partial.edges += projectEdges
            partial.findings += ruleFindings + organizationFindings
            partial.recommendations += ruleRecommendations + organizationRecommendations
            partial.didRunRules = true

            let packageResult: ([Finding], [Recommendation], [PackageCleanupCandidate])
            if let packageTask {
                packageResult = await packageTask.value
            } else {
                packageResult = ([], [], [])
            }
            finishStage("Rules and packages")
            partial.findings += packageResult.0
            partial.recommendations += packageResult.1
            partial.packageCandidates = packageResult.2
            try Task.checkCancellation()

            var filesByID: [String: FileRecord] = [:]
            for file in files {
                filesByID[file.id] = file
            }
            let memoryAdjustedRecommendations = try await memory.applyMemory(to: partial.recommendations, filesByID: filesByID)
            partial.recommendations = memoryAdjustedRecommendations
            partial.didApplyMemory = true
            try Task.checkCancellation()

            let aiRecommendations: [AIRecommendationPayload]
            if includeAI {
                await notifyProgress(4, String(localized: "Running AI classification"))
                do {
                    aiRecommendations = try await aiGateway.classify(
                        findings: partial.findings,
                        filesByID: filesByID,
                        settings: providerSettings,
                        contentSummaries: contentSummaries
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    logger.warning("AI classification failed: \(error.localizedDescription, privacy: .public). Proceeding without AI recommendations.")
                    aiRecommendations = []
                }
            } else {
                aiRecommendations = []
            }

            let plan = await planner.makePlan(
                sessionID: session.id,
                recommendations: memoryAdjustedRecommendations,
                filesByID: filesByID,
                aiRecommendations: aiRecommendations
            )
            finishStage("Memory, AI, and plan")
            return try await finalizeScan(
                session: &session,
                files: files,
                roots: roots,
                findings: partial.findings,
                recommendations: partial.recommendations,
                plan: plan,
                projects: partial.projects,
                edges: partial.edges,
                fingerprints: partial.fingerprints,
                contentSummaries: partial.contentSummaries,
                packageCandidates: partial.packageCandidates,
                errors: errors,
                notices: partial.notices,
                wasCancelled: false,
                notifyProgress: notifyProgress
            )
        } catch is CancellationError {
            // A stopped scan keeps what it found so far. Cancelling used to
            // discard every result, and because ~/Library is crawled last, a
            // person who stopped a slow scan always saw an empty review.
            if let packageTask {
                // Cancel and drop: ProcessRunner does not observe task
                // cancellation, so awaiting the value would stall the unwind
                // until the probe's own timeout elapses. The result is not
                // needed — the scan is stopping.
                packageTask.cancel()
            }
            session.completedAt = Date()
            session.status = .cancelled
            // The rule pass is one fast in-memory sweep. Without it, a stop
            // during the long crawl — the most common cancel point — would
            // still show an empty review. Run it off the cancelled task so
            // `detectProjects`/`analyze`'s own cancellation checks don't throw;
            // duplicates are skipped: that stage is the expensive one, and its
            // in-flight work is not recoverable after cancellation anyway.
            if !partial.didRunRules, !partial.files.isEmpty {
                let ruleEngine = self.ruleEngine
                let organizationPlanner = self.organizationPlanner
                let projectDetector = self.projectDetector
                let partialFiles = partial.files
                let partialSessionID = session.id
                let partialPosture = posture
                let analysis = try? await Task.detached { () -> CancelledScanAnalysis in
                    let projects = try await projectDetector.detectProjects(in: partialFiles)
                    let (ruleFindings, ruleRecommendations) = try await ruleEngine.analyze(
                        files: partialFiles, projects: projects, sessionID: partialSessionID, posture: partialPosture)
                    let (organizationFindings, organizationRecommendations) = try await organizationPlanner
                        .suggestOrganization(files: partialFiles, sessionID: partialSessionID)
                    return CancelledScanAnalysis(
                        projects: projects,
                        findings: ruleFindings + organizationFindings,
                        recommendations: ruleRecommendations + organizationRecommendations)
                }.value
                if let analysis {
                    partial.projects = analysis.projects
                    partial.findings += analysis.findings
                    partial.recommendations += analysis.recommendations
                }
            }
            var filesByID: [String: FileRecord] = [:]
            for file in partial.files {
                filesByID[file.id] = file
            }
            // "Never" rules must hold for a stopped scan too: the partial review
            // is still shown, and a rule the person set must not reappear as a
            // destructive action just because the scan was interrupted. Memory
            // rules are cheap to apply (one store read plus an in-memory map).
            if !partial.didApplyMemory {
                do {
                    partial.recommendations = try await memory.applyMemory(
                        to: partial.recommendations, filesByID: filesByID)
                    partial.didApplyMemory = true
                } catch {
                    logger.warning(
                        "Memory rules could not be applied to the stopped scan: \(error.localizedDescription, privacy: .public)")
                }
            }
            let plan = await planner.makePlan(
                sessionID: session.id,
                recommendations: partial.recommendations,
                filesByID: filesByID,
                aiRecommendations: []
            )
            do {
                let (partialOutcome, partialPlan) = try await finalizeScan(
                    session: &session,
                    files: partial.files,
                    roots: roots,
                    findings: partial.findings,
                    recommendations: partial.recommendations,
                    plan: plan,
                    projects: partial.projects,
                    edges: partial.edges,
                    fingerprints: partial.fingerprints,
                    contentSummaries: partial.contentSummaries,
                    packageCandidates: partial.packageCandidates,
                    errors: partial.errors,
                    notices: partial.notices,
                    wasCancelled: true,
                    persistRecords: false,
                    notifyProgress: notifyProgress
                )
                return (partialOutcome, partialPlan)
            } catch {
                session.status = .failed
                try? await store.saveScanSession(session)
                throw error
            }
        } catch {
            if let packageTask {
                packageTask.cancel()
            }
            session.completedAt = Date()
            session.status = .failed
            try? await store.saveScanSession(session)
            throw error
        }
    }

    /// Single persistence + snapshot + outcome path shared by the full crawl
    /// and the system-clean pipelines. Previously each pipeline duplicated
    /// this block (~60 lines), and they drifted (different snapshot shapes).
    private func finalizeScan(
        session: inout ScanSession,
        files: [FileRecord],
        roots: [URL],
        findings: [Finding],
        recommendations: [Recommendation],
        plan: Plan,
        projects: [ProjectUnit],
        edges: [RelationshipEdge],
        fingerprints: [FileFingerprint],
        contentSummaries: [ContentSummary],
        packageCandidates: [PackageCleanupCandidate],
        errors: Int,
        notices: [ScanNotice] = [],
        wasCancelled: Bool = false,
        persistRecords: Bool = true,
        notifyProgress: @Sendable (Int, String) async -> Void
    ) async throws -> (outcome: ScanOutcome, plan: Plan) {
        await notifyProgress(5, String(localized: "Finalizing scan"))

        let snapshot = StorageSnapshot(
            id: UUID().uuidString,
            createdAt: Date(),
            totalBytes: files.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) },
            bytesByCategory: Dictionary(grouping: findings, by: \.category)
                .mapValues { $0.reduce(Int64(0)) { $0 + $1.bytesReclaimable } },
            bytesByRootPath: Dictionary(roots.map { root in
                let prefix = root.path + "/"
                let bytes = files.filter { $0.displayPath == root.path || $0.displayPath.hasPrefix(prefix) }.reduce(Int64(0)) { $0 + $1.sizeBytes }
                return (root.path, bytes)
            }, uniquingKeysWith: +),
            bytesByProject: {
                var bytesByProject: [String: Int64] = [:]
                for project in projects {
                    bytesByProject[project.name, default: 0] += project.totalBytes
                }
                return bytesByProject
            }(),
            removedBytesThroughApp: 0
        )

        session.completedAt = Date()
        session.status = wasCancelled ? .cancelled : .completed
        session.totalFilesSeen = files.count
        session.totalBytesSeen = snapshot.totalBytes
        session.errorsCount = errors

        // The session row is small and records the cancellation; the bulk rows
        // are what made Stop look unresponsive (up to a million records in one
        // transaction). A stopped scan keeps its partial results in memory for
        // review and execution, so skip the bulk writes when asked.
        try await store.saveScanSession(session)
        if persistRecords {
            try await store.saveFileRecords(files)
            try await store.saveFingerprints(fingerprints)
            try await store.saveContentSummaries(contentSummaries)
            try await store.saveProjects(projects)
            try await store.saveRelationshipEdges(edges)
            try await store.saveFindings(findings)
            try await store.saveRecommendations(recommendations)
            try await store.savePlan(plan)
            try await store.saveStorageSnapshot(snapshot)
        }

        var outcome = ScanOutcome(
            session: session,
            files: files,
            fingerprints: fingerprints,
            contentSummaries: contentSummaries,
            projects: projects,
            edges: edges,
            findings: findings,
            recommendations: recommendations,
            snapshot: snapshot,
            packageCandidates: packageCandidates
        )
        outcome.wasCancelled = wasCancelled
        outcome.notices = notices
        return (outcome, plan)
    }

    /// Pipeline for mo clean known-path sections. Skips duplicate/project/
    /// organization/package stages (irrelevant for system caches) but still
    /// applies memory rules, optional AI, planner, snapshot, and persistence so
    /// the Review → Execute → Undo flow works unchanged. Mirrors the section
    /// result into `partial` as soon as it exists, so a cancellation after the
    /// scan still finalizes what the section found.
    private func scanSystemCleanSection(
        section: MoCleanScanner.SystemCleanSection,
        session: ScanSession,
        roots: [URL],
        providerSettings: ProviderSettings,
        includeAI: Bool,
        partial: inout AccumulatedScan,
        finishStage: (String) -> Void,
        notifyProgress: @Sendable (Int, String) async -> Void
    ) async throws -> (outcome: ScanOutcome, plan: Plan) {
        await notifyProgress(2, String(localized: "Scanning known paths"))
        var session = session
        let result = await moCleanScanner.scan(section: section, sessionID: session.id)
        finishStage("Known-path scan")
        partial.files = result.files
        partial.errors = result.crawlErrors
        partial.findings = result.findings
        partial.recommendations = result.recommendations
        partial.notices += result.notices
        // Section findings come from the section's own classification; the
        // rule engine must not run over these files on the cancellation path.
        partial.didRunRules = true
        await notifyProgress(3, String(localized: "Analyzing findings"))
        try Task.checkCancellation()

        let files = result.files
        var filesByID: [String: FileRecord] = [:]
        for file in files {
            filesByID[file.id] = file
        }
        let memoryAdjustedRecommendations = try await memory.applyMemory(to: result.recommendations, filesByID: filesByID)
        partial.recommendations = memoryAdjustedRecommendations
        partial.didApplyMemory = true
        try Task.checkCancellation()

        let aiRecommendations: [AIRecommendationPayload]
        if includeAI {
            await notifyProgress(4, String(localized: "Running AI classification"))
            do {
                aiRecommendations = try await aiGateway.classify(
                    findings: result.findings,
                    filesByID: filesByID,
                    settings: providerSettings,
                    contentSummaries: []
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.warning("AI classification failed: \(error.localizedDescription, privacy: .public). Proceeding without AI recommendations.")
                aiRecommendations = []
            }
        } else {
            aiRecommendations = []
        }

        let plan = await planner.makePlan(
            sessionID: session.id,
            recommendations: memoryAdjustedRecommendations,
            filesByID: filesByID,
            aiRecommendations: aiRecommendations
        )
        return try await finalizeScan(
            session: &session,
            files: files,
            roots: roots,
            findings: result.findings,
            recommendations: memoryAdjustedRecommendations,
            plan: plan,
            projects: [],
            edges: [],
            fingerprints: [],
            contentSummaries: [],
            packageCandidates: [],
            errors: result.crawlErrors,
            notices: partial.notices,
            wasCancelled: false,
            notifyProgress: notifyProgress
        )
    }
}
