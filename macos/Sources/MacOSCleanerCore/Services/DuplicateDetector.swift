import Foundation
import os
@preconcurrency import Vision

/// Sendable wrapper for a Vision feature print. VNFeaturePrintObservation is
/// not marked Sendable, but it is an immutable value object once produced —
/// safe to pass between concurrency domains.
public struct ImageFeaturePrint: @unchecked Sendable {
    let observation: VNFeaturePrintObservation
}

/// How exact duplicate groups should be resolved by default.
public enum DuplicateStrategy: String, Codable, Sendable, CaseIterable {
    /// Fold duplicates onto the newest copy as APFS clones: nothing is
    /// deleted, every path and its metadata stay, and the space is reclaimed
    /// immediately. Undo re-splits a folded copy into a real file.
    case apfsClone
    /// Move duplicate copies to Trash (the classic resolution).
    case moveToTrash
}

public struct DuplicateAnalysis: Sendable {
    public var fingerprints: [FileFingerprint]
    public var findings: [Finding]
    public var recommendations: [Recommendation]
    public var edges: [RelationshipEdge]
}

public actor DuplicateDetector {
    private let policy: PathSafetyPolicy
    /// Persistent full-hash cache. A cached hash is reused only when size and
    /// mtime both match, so rescans stop re-reading unchanged files.
    private let hashCache: SQLiteStore?
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "DuplicateDetector")

    /// Pairwise feature-print distance at or below which two images count as
    /// visually similar. The current feature print (revision 2) scores 0 for
    /// identical images and about 1 for unrelated ones; a retake scores about 0.3.
    /// 0.5 is the cutoff the iOS app ships with. The old cutoff of 8 came from
    /// revision 1's scale and matched every pair of images.
    static let nearDuplicateDistanceThreshold: Float = 0.5
    /// Images fingerprinted per scan, largest first. A feature print costs tens of
    /// milliseconds, so this bounds the stage to minutes on any library.
    static let maxNearDuplicateImages = 20_000
    /// Each image is compared with this many neighbours in time order. Similar
    /// shots (bursts, retakes, edits) sit next to each other in time. Comparing
    /// every pair grew as n squared and ran for hours on a large home folder.
    static let nearDuplicateWindow = 32
    /// Hash workers per size group. Bounded so a huge group cannot saturate
    /// every cooperative thread; disk throughput is usually the limit anyway.
    static let hashWorkerCount = 4

    public init(policy: PathSafetyPolicy = PathSafetyPolicy(), hashCache: SQLiteStore? = nil) {
        self.policy = policy
        self.hashCache = hashCache
    }

    /// App and system state under ~/Library (containers, simulators, device
    /// support) is never a duplicate target: other software owns those bytes.
    static func isInsideUserLibrary(_ url: URL) -> Bool {
        let library = userLibraryPath
        let path = url.standardizedFileURL.path.lowercased()
        return path == library || path.hasPrefix(library + "/")
    }

    private static let userLibraryPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true).standardizedFileURL.path.lowercased()

    private func isDuplicateCandidate(_ file: FileRecord, maxSize: Int64) -> Bool {
        guard file.kind == .regularFile, file.sizeBytes > 0, file.sizeBytes <= maxSize,
              !Self.isCloudPlaceholder(file), !Self.isInsideUserLibrary(file.url) else {
            return false
        }
        if case .allow = policy.decide(target: file.url, isDirectory: false) {
            return true
        }
        return false
    }

    /// True when the file is a dataless cloud placeholder (iCloud/cloud-synced).
    /// Placeholders have no local content, hashing them would trigger a download,
    /// and they must never be proposed for trashing as duplicates. Trusts the
    /// crawler-populated flag — re-statting every candidate doubled syscalls.
    public static func isCloudPlaceholder(_ file: FileRecord) -> Bool {
        file.isCloudPlaceholder
    }

    /// - Parameters:
    ///   - strategy: how exact duplicate groups should be resolved. `apfsClone`
    ///     emits non-destructive fold recommendations; `moveToTrash` preserves
    ///     the classic behavior.
    /// - Throws: `CancellationError` when the scan is cancelled mid-analysis.
    public func analyze(
        files: [FileRecord],
        sessionID: String,
        strategy: DuplicateStrategy = .apfsClone
    ) async throws -> DuplicateAnalysis {
        // Skip files over 2GB for full hashing — extremely expensive and rarely intentional duplicates
        let maxFullHashSize: Int64 = 2_000_000_000
        // One autorelease pool per file: the path and policy checks autorelease URL
        // objects, and one pass over a million records kept about 3 GB of them alive.
        let candidates = files.filter { file in autoreleasepool { isDuplicateCandidate(file, maxSize: maxFullHashSize) } }

        // Paths sharing a device+inode ARE the same storage (hard links).
        // Hashing both and recommending a trash would free zero bytes, so
        // deduplicate by storage identity before grouping. Records without
        // identity fields are kept (conservative — they hash like any other).
        var seenInodes = Set<String>()
        var uniqueStorage: [FileRecord] = []
        uniqueStorage.reserveCapacity(candidates.count)
        for file in candidates {
            if let device = file.identity.deviceIdentifier,
               let inode = file.identity.inodeIdentifier {
                guard seenInodes.insert("\(device)-\(inode)").inserted else { continue }
            }
            uniqueStorage.append(file)
        }

        // Group by LOGICAL size: two identical sparse files can report
        // different allocated sizes and would never meet in an
        // allocated-size bucket. Reclaimable bytes stay allocated-size based.
        let sizeGroups = Dictionary(grouping: uniqueStorage, by: { $0.identity.sizeBytes ?? $0.sizeBytes })
            .values.filter { $0.count > 1 }
        var findings: [Finding] = []
        var recommendations: [Recommendation] = []
        var edges: [RelationshipEdge] = []

        // All fingerprints, collected from parallel workers.
        var fingerprints: [FileFingerprint] = []
        // Files that share a full SHA-256 with at least one other candidate,
        // keyed by hash → group members.
        var fullGroups: [String: [(file: FileRecord, quick: String?)]] = [:]

        for sizeGroup in sizeGroups {
            // Cooperative cancellation between groups.
            try Task.checkCancellation()
            var quickGroups: [String: [FileRecord]] = [:]
            var quickHashFailures: [FileRecord] = []
            for file in sizeGroup {
                do {
                    let quick = try FingerprintService.quickHash(for: file.url, sizeBytes: file.sizeBytes)
                    quickGroups[quick, default: []].append(file)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    logger.warning("Quick hash failed for \(file.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    quickHashFailures.append(file)
                }
            }
            // Quick hashing is cheap (≤3 chunks); only files sharing a quick
            // hash proceed to expensive full hashing.
            let fullHashCandidates = quickGroups.values.filter { $0.count > 1 }.flatMap { $0 } + quickHashFailures

            // Cache pass: a cached full hash is reused only when size AND
            // mtime both match, so unchanged files skip the disk entirely.
            var resolvedHashes: [String: String] = [:]
            var pendingHash: [String: FileRecord] = [:]
            for file in fullHashCandidates {
                if let hashCache,
                   let cached = try? await hashCache.cachedFullHash(
                        forPath: file.url.path,
                        sizeBytes: file.sizeBytes,
                        modifiedAt: file.modifiedAt
                   ) {
                    resolvedHashes[file.id] = cached
                } else {
                    pendingHash[file.id] = file
                }
            }

            // Full-hash the remaining survivors with a bounded worker pool. Previously every
            // hash funneled through one actor hop per file, serializing at
            // single-stream disk speed regardless of cores.
            var freshHashes: [String: String?] = [:]
            var iterator = pendingHash.values.makeIterator()
            await withTaskGroup(of: (FileRecord, String?).self) { group in
                for _ in 0..<Self.hashWorkerCount {
                    guard let file = iterator.next() else { break }
                    group.addTask { Self.fullHashTask(for: file) }
                }
                while let (file, full) = await group.next() {
                    freshHashes[file.id] = .some(full)
                    if let next = iterator.next() {
                        group.addTask { Self.fullHashTask(for: next) }
                    }
                }
            }
            // Persist fresh hashes so the next scan skips re-reading these files.
            if let hashCache, !freshHashes.isEmpty {
                let entries = freshHashes.compactMap { entry -> FileHashCacheEntry? in
                    guard let hash = entry.value, let file = pendingHash[entry.key] else { return nil }
                    return FileHashCacheEntry(
                        path: file.url.path,
                        sizeBytes: file.sizeBytes,
                        modifiedAt: file.modifiedAt,
                        fullHash: hash
                    )
                }
                try? await hashCache.saveFileHashes(entries)
            }
            for (fileID, result) in freshHashes {
                if let hash = result {
                    resolvedHashes[fileID] = hash
                } else {
                    // Hashing failed (or was cancelled mid-read) — surface as a
                    // failure fingerprint instead of silently dropping the file.
                    if let file = pendingHash[fileID] {
                        fingerprints.append(FileFingerprint(
                            fileID: file.id,
                            sizeBytes: file.sizeBytes,
                            quickHash: nil,
                            fullHash: nil,
                            imagePerceptualHash: nil,
                            videoKeyframeHashes: [],
                            hashStatus: .failed
                        ))
                    }
                }
            }
            // Collect into hash groups; files that were neither resolved nor
            // hashed (quick-hash failures) simply do not group.
            for file in fullHashCandidates {
                if let full = resolvedHashes[file.id] {
                    fullGroups[full, default: []].append((file, nil))
                }
            }
            try Task.checkCancellation()
        }

        // Emit one finding per exact-duplicate group (full SHA-256 match).
        for (hash, members) in fullGroups where members.count > 1 {
            let files = members.map(\.file).sorted { lhs, rhs in
                (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast)
            }
            guard let keep = files.first else { continue }
            let duplicates = Array(files.dropFirst())
            emitExactDuplicateGroup(
                keep: keep,
                duplicates: duplicates,
                hash: hash,
                sessionID: sessionID,
                strategy: strategy,
                into: &findings,
                recommendationsOut: &recommendations,
                edgesOut: &edges
            )
            // Every member of an exact-match group carries a confirmed fingerprint.
            for file in files {
                fingerprints.append(FileFingerprint(
                    fileID: file.id,
                    sizeBytes: file.sizeBytes,
                    quickHash: nil,
                    fullHash: hash,
                    imagePerceptualHash: nil,
                    videoKeyframeHashes: [],
                    hashStatus: .fullHashConfirmed
                ))
            }
        }

        // Near-duplicate phase: group IMAGES by pairwise Vision feature-print
        // distance. The previous implementation hashed each print's raw bytes and
        // grouped by equality — bit-identical encodings only, which is exact-match
        // in disguise and never fired for genuinely similar-but-different files.
        try await detectNearDuplicates(
            files: uniqueStorage,
            existingFindings: findings,
            sessionID: sessionID,
            into: &findings,
            recommendationsOut: &recommendations,
            edgesOut: &edges
        )

        return DuplicateAnalysis(
            fingerprints: fingerprints,
            findings: findings,
            recommendations: recommendations,
            edges: edges
        )
    }

    /// Full-hashes one file off the actor; `nil` result means hashing failed
    /// (or was cancelled mid-read, which surfaces as a failure fingerprint).
    private static func fullHashTask(for file: FileRecord) -> (FileRecord, String?) {
        do {
            let full = try FingerprintService.fullHash(for: file.url)
            return (file, full)
        } catch {
            return (file, nil)
        }
    }

    /// Keeper selection rule shared by scan emission and plan-time rebuilds:
    /// the newest copy wins, except a cloud-synced copy is never the keeper
    /// while a local copy exists — folding a local file onto a cloud-synced
    /// twin would make the sync engine see an inode swap.
    static func selectKeeper(sortedNewestFirst members: [FileRecord]) -> (keeper: FileRecord, duplicates: [FileRecord])? {
        guard let newest = members.first, members.count > 1 else { return nil }
        let keeper = members.first { $0.cloudProvider == nil } ?? newest
        return (keeper, members.filter { $0.id != keeper.id })
    }

    /// Newest copy of an exact-match group wins the keeper slot — the same
    /// ordering and local-preference rule the detector uses when it emits findings.
    public static func keeperAndDuplicates(of targetFileIDs: [String], filesByID: [String: FileRecord]) -> (keeper: FileRecord, duplicates: [FileRecord])? {
        let records = targetFileIDs.compactMap { filesByID[$0] }
        let sorted = records.sorted { lhs, rhs in
            (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast)
        }
        return selectKeeper(sortedNewestFirst: sorted)
    }

    /// Duplicates that could be folded onto `keep`: keeper and duplicate both
    /// local (not cloud-synced — sync engines must not see inode swaps), same
    /// volume, on a clone-capable volume. Final eligibility is re-verified at
    /// execution time. Static and nonisolated so the planner and the
    /// per-group strategy switch share one eligibility rule.
    public static func foldEligibleDuplicates(duplicates: [FileRecord], keep: FileRecord) -> [FileRecord] {
        guard keep.cloudProvider == nil,
              APFSCloneService.volumeSupportsClones(at: keep.url),
              let keepDevice = keep.identity.deviceIdentifier else {
            return []
        }
        return duplicates.filter { duplicate in
            guard let duplicateDevice = duplicate.identity.deviceIdentifier,
                  keepDevice == duplicateDevice else {
                return false
            }
            return duplicate.cloudProvider == nil
                && APFSCloneService.volumeSupportsClones(at: duplicate.url)
        }
    }

    private func emitExactDuplicateGroup(
        keep: FileRecord,
        duplicates: [FileRecord],
        hash: String,
        sessionID: String,
        strategy: DuplicateStrategy,
        into findings: inout [Finding],
        recommendationsOut: inout [Recommendation],
        edgesOut: inout [RelationshipEdge]
    ) {
        let risk = duplicates.contains(where: { $0.cloudProvider != nil }) ? RiskLevel.high : RiskLevel.low
        let findingID = UUID().uuidString
        let bytes = duplicates.reduce(Int64(0)) { $0 + $1.sizeBytes }
        // Re-resolve the keeper with the shared rule: a cloud-synced copy
        // never keeps while a local copy exists.
        guard let (resolvedKeeper, resolvedDuplicates) = Self.selectKeeper(sortedNewestFirst: [keep] + duplicates) else {
            return
        }
        let summary: String
        switch strategy {
        case .apfsClone:
            summary = String(localized: "\(groupSize(keep: resolvedKeeper, duplicates: resolvedDuplicates)) exact duplicate files, confirmed by full SHA-256. Their space can be reclaimed without deleting anything.", comment: "Exact duplicate finding summary")
        case .moveToTrash:
            summary = String(localized: "\(groupSize(keep: resolvedKeeper, duplicates: resolvedDuplicates)) exact duplicate files, confirmed by full SHA-256.", comment: "Exact duplicate finding summary")
        }
        findings.append(Finding(
            id: findingID,
            scanSessionID: sessionID,
            category: .duplicate,
            severity: risk,
            confidence: 0.99,
            bytesReclaimable: bytes,
            summary: summary,
            evidence: ["kept_file": resolvedKeeper.displayPath, "hash": hash, "bytes": String(bytes)],
            targetFileIDs: ([resolvedKeeper] + resolvedDuplicates).map(\.id)
        ))

        let foldEligible = strategy == .apfsClone
            ? Self.foldEligibleDuplicates(duplicates: resolvedDuplicates, keep: resolvedKeeper) : []
        if !foldEligible.isEmpty {
            recommendationsOut.append(Recommendation(
                id: UUID().uuidString,
                findingID: findingID,
                actionType: .cloneDeduplicate,
                targetFileIDs: foldEligible.map(\.id),
                confidence: 0.99,
                risk: .low,
                reason: String(localized: "Fold each copy onto the newest file as an APFS clone. Every file keeps its name, contents and metadata. Nothing is deleted, the space is reclaimed immediately, and this can be undone.", comment: "Exact duplicate clone-fold recommendation reason"),
                expectedBytesReclaimed: foldEligible.reduce(Int64(0)) { $0 + $1.sizeBytes },
                requiresConfirmation: true,
                llmTraceID: nil,
                policyTraceID: "duplicate_apfs_clone",
                destination: resolvedKeeper.url
            ))
        }
        // Members that cannot be folded (cloud-synced, other volume, or a
        // trash-strategy scan) keep the classic trash recommendation.
        let eligibleIDs = Set(foldEligible.map(\.id))
        let trashTargets = strategy == .moveToTrash ? resolvedDuplicates : resolvedDuplicates.filter { !eligibleIDs.contains($0.id) }
        if !trashTargets.isEmpty {
            recommendationsOut.append(Recommendation(
                id: UUID().uuidString,
                findingID: findingID,
                actionType: .moveToTrash,
                targetFileIDs: trashTargets.map(\.id),
                confidence: 0.99,
                risk: risk,
                reason: String(localized: "These files have the same size and full content hash. Keep the newest copy and move duplicate copies to Trash.", comment: "Exact duplicate recommendation reason"),
                expectedBytesReclaimed: trashTargets.reduce(Int64(0)) { $0 + $1.sizeBytes },
                requiresConfirmation: true,
                llmTraceID: nil,
                policyTraceID: "duplicate_full_sha256"
            ))
        }
        for duplicate in resolvedDuplicates {
            edgesOut.append(RelationshipEdge(
                id: "\(resolvedKeeper.id)-\(duplicate.id)-duplicate",
                fromFileID: resolvedKeeper.id,
                toFileID: duplicate.id,
                edgeType: .duplicate,
                confidence: 0.99,
                evidence: "Full SHA-256 hash matched."
            ))
        }
    }

    private func groupSize(keep: FileRecord, duplicates: [FileRecord]) -> Int {
        duplicates.count + 1
    }

    /// Groups images whose Vision feature-print distance to a group's first image
    /// is under the threshold. At most `nearDuplicateWindow` distance calls per
    /// image, over at most `maxNearDuplicateImages` images.
    private func detectNearDuplicates(
        files: [FileRecord],
        existingFindings: [Finding],
        sessionID: String,
        into findings: inout [Finding],
        recommendationsOut: inout [Recommendation],
        edgesOut: inout [RelationshipEdge]
    ) async throws {
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "heic", "webp"]
        let images = files.filter { file in
            guard let ext = file.fileExtension?.lowercased(), imageExtensions.contains(ext) else {
                return false
            }
            return true
        }
        guard images.count > 1 else { return }

        var prints: [(file: FileRecord, print: ImageFeaturePrint)] = []
        var iterator = images.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(Self.maxNearDuplicateImages).makeIterator()
        await withTaskGroup(of: (FileRecord, ImageFeaturePrint?).self) { group in
            for _ in 0..<Self.hashWorkerCount {
                guard let file = iterator.next() else { break }
                group.addTask { (file, await FingerprintService.featurePrint(for: file.url)) }
            }
            while let (file, print) = await group.next() {
                if let print {
                    prints.append((file, print))
                }
                if let next = iterator.next() {
                    group.addTask { (next, await FingerprintService.featurePrint(for: next.url)) }
                }
            }
        }
        guard prints.count > 1 else { return }
        prints.sort { ($0.file.modifiedAt ?? .distantPast) < ($1.file.modifiedAt ?? .distantPast) }

        // Each group is one anchor plus the later images (by modified time) within
        // the threshold of that anchor. Grouping is not transitive, so a run of
        // slowly changing shots never chains into one group of unrelated images.
        var visited = Set<Int>()
        var components: [[Int]] = []
        for i in prints.indices where !visited.contains(i) {
            try Task.checkCancellation()
            visited.insert(i)
            var group = [i]
            for other in (i + 1)..<min(i + 1 + Self.nearDuplicateWindow, prints.endIndex) where !visited.contains(other) {
                var distance: Float = 0
                guard (try? prints[i].print.observation.computeDistance(&distance, to: prints[other].print.observation)) != nil,
                    distance < Self.nearDuplicateDistanceThreshold
                else { continue }
                visited.insert(other)
                group.append(other)
            }
            if group.count > 1 { components.append(group) }
        }

        for component in components {
            let members = component.map { prints[$0].file }.sorted { lhs, rhs in
                (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast)
            }
            guard let keep = members.first else { continue }
            let nearDuplicates = Array(members.dropFirst())
            // Skip groups already fully covered by an exact-match finding.
            let memberIDs = Set(members.map(\.id))
            if existingFindings.contains(where: { finding in
                Set(finding.targetFileIDs).isSuperset(of: memberIDs)
            }) {
                continue
            }
            let bytes = nearDuplicates.reduce(Int64(0)) { $0 + $1.sizeBytes }
            let findingID = UUID().uuidString
            findings.append(Finding(
                id: findingID,
                scanSessionID: sessionID,
                category: .duplicate,
                severity: .low,
                confidence: 0.85,
                bytesReclaimable: bytes,
                summary: String(localized: "\(members.count) visually similar images detected.", comment: "Near-duplicate finding summary"),
                evidence: ["kept_file": keep.displayPath, "bytes": String(bytes)],
                targetFileIDs: members.map(\.id)
            ))
            recommendationsOut.append(Recommendation(
                id: UUID().uuidString,
                findingID: findingID,
                actionType: .moveToTrash,
                targetFileIDs: nearDuplicates.map(\.id),
                confidence: 0.85,
                risk: .low,
                reason: String(localized: "These images look very similar but are not byte-identical. Verify before trashing; keep the newest.", comment: "Near-duplicate recommendation reason"),
                expectedBytesReclaimed: bytes,
                requiresConfirmation: true,
                llmTraceID: nil,
                policyTraceID: "duplicate_feature_print_distance"
            ))
            for dup in nearDuplicates {
                edgesOut.append(RelationshipEdge(
                    id: "\(keep.id)-\(dup.id)-nearDuplicate",
                    fromFileID: keep.id,
                    toFileID: dup.id,
                    edgeType: .nearDuplicateOf,
                    confidence: 0.85,
                    evidence: "Feature-print distance < \(String(format: "%.1f", Self.nearDuplicateDistanceThreshold))."
                ))
            }
        }
    }
}
