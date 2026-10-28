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

        public init(phase: String, currentStep: Int, totalSteps: Int) {
            self.phase = phase
            self.currentStep = currentStep
            self.totalSteps = max(1, totalSteps)
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

        // mo clean known-path sections take a separate, simpler pipeline:
        // crawl known paths → classify by section → memory/AI/planner/snapshot/store.
        if let section = mode.systemCleanSection {
            return try await scanSystemCleanSection(
                section: section,
                session: session,
                roots: roots,
                providerSettings: providerSettings,
                includeAI: includeAI,
                notifyProgress: notifyProgress
            )
        }

        // Cooperative cancellation: each pipeline stage checks before doing heavy work so
        // cancelScan() stops the scan promptly instead of running every stage to completion.
        do {
            try Task.checkCancellation()
            await notifyProgress(2, String(localized: "Crawling files"))
            let (files, errors) = await crawler.crawl(rootURLs: roots, sessionID: session.id)
            await notifyProgress(3, String(localized: "Analyzing findings"))
            if errors > 0 {
                let message = errors == 1
                    ? String(localized: "Crawl completed with 1 error across \(files.count) files.", comment: "Log: single crawl error")
                    : String(localized: "Crawl completed with \(errors) errors across \(files.count) files.", comment: "Log: multiple crawl errors")
                logger.warning("\(message, privacy: .public)")
            }
            try Task.checkCancellation()

            // Pipeline: crawl first (needed by all subsequent stages), then parallelize independent stages.
            // Content extraction, duplicate detection, and project detection are independent of each other.
            let projects = await projectDetector.detectProjects(in: files)
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
            try Task.checkCancellation()

            let projectEdges = await projectDetector.buildEdges(files: files, projects: projects)
            let (ruleFindings, ruleRecommendations) = await ruleEngine.analyze(files: files, projects: projects, sessionID: sessionID, posture: posture)
            let (organizationFindings, organizationRecommendations) = await organizationPlanner.suggestOrganization(files: files, sessionID: sessionID)
            let packageResult: ([Finding], [Recommendation], [PackageCleanupCandidate])
            // Whole-home and developer scans include the package managers' own
            // cleanup commands (dry-run only here; nothing runs until approved).
            if mode == .developerCleanup || mode == .homeFolder {
                packageResult = await packageScanner.scan(sessionID: session.id)
            } else {
                packageResult = ([], [], [])
            }
            try Task.checkCancellation()

            let allFindings = duplicateAnalysis.findings + ruleFindings + organizationFindings + packageResult.0
            var filesByID: [String: FileRecord] = [:]
            for file in files {
                filesByID[file.id] = file
            }
            let deterministicRecommendations = duplicateAnalysis.recommendations + ruleRecommendations + organizationRecommendations + packageResult.1
            let memoryAdjustedRecommendations = try await memory.applyMemory(to: deterministicRecommendations, filesByID: filesByID)
            try Task.checkCancellation()

            let aiRecommendations: [AIRecommendationPayload]
            if includeAI {
                await notifyProgress(4, String(localized: "Running AI classification"))
                do {
                    aiRecommendations = try await aiGateway.classify(
                        findings: allFindings,
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
        return try await finalizeScan(
                session: &session,
                files: files,
                roots: roots,
                findings: allFindings,
                recommendations: memoryAdjustedRecommendations,
                plan: plan,
                projects: projects,
                edges: projectEdges + duplicateAnalysis.edges,
                fingerprints: duplicateAnalysis.fingerprints,
                contentSummaries: contentSummaries,
                packageCandidates: packageResult.2,
                errors: errors,
                notifyProgress: notifyProgress
            )
        } catch is CancellationError {
            session.completedAt = Date()
            session.status = .cancelled
            try? await store.saveScanSession(session)
            throw CancellationError()
        } catch {
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
        session.status = .completed
        session.totalFilesSeen = files.count
        session.totalBytesSeen = snapshot.totalBytes
        session.errorsCount = errors

        try await store.saveScanSession(session)
        try await store.saveFileRecords(files)
        try await store.saveFingerprints(fingerprints)
        try await store.saveContentSummaries(contentSummaries)
        try await store.saveProjects(projects)
        try await store.saveRelationshipEdges(edges)
        try await store.saveFindings(findings)
        try await store.saveRecommendations(recommendations)
        try await store.savePlan(plan)
        try await store.saveStorageSnapshot(snapshot)

        let outcome = ScanOutcome(
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
        return (outcome, plan)
    }

    /// Pipeline for mo clean known-path sections. Skips duplicate/project/
    /// organization/package stages (irrelevant for system caches) but still
    /// applies memory rules, optional AI, planner, snapshot, and persistence so
    /// the Review → Execute → Undo flow works unchanged.
    private func scanSystemCleanSection(
        section: MoCleanScanner.SystemCleanSection,
        session: ScanSession,
        roots: [URL],
        providerSettings: ProviderSettings,
        includeAI: Bool,
        notifyProgress: @Sendable (Int, String) async -> Void
    ) async throws -> (outcome: ScanOutcome, plan: Plan) {
        await notifyProgress(2, String(localized: "Scanning known paths"))
        var session = session
        let result = await moCleanScanner.scan(section: section, sessionID: session.id)
        await notifyProgress(3, String(localized: "Analyzing findings"))
        try Task.checkCancellation()

        let files = result.files
        var filesByID: [String: FileRecord] = [:]
        for file in files {
            filesByID[file.id] = file
        }
        let memoryAdjustedRecommendations = try await memory.applyMemory(to: result.recommendations, filesByID: filesByID)
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
            notifyProgress: notifyProgress
        )
    }
}
