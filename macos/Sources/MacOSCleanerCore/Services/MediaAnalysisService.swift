import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
@preconcurrency import Vision

struct ImageMeasurement: @unchecked Sendable {
    var facts: MediaFacts
    var feature: VNFeaturePrintObservation?
    var perceptualHash: UInt64
}

public actor MediaAnalysisService {
    private let photos: PhotoLibraryService
    private let store: SQLiteStore
    public init(photos: PhotoLibraryService, store: SQLiteStore) {
        self.photos = photos
        self.store = store
    }

    public func analyze(
        _ input: [ReviewItem], scopeID: String, settings: CleanupSettings,
        progress: @Sendable (CleanupProgress) async -> Void
    ) async throws -> AnalysisResult {
        var items = input
        var images: [String: ImageMeasurement] = [:]
        var hashes: [String: [ReviewItem]] = [:]
        let hashCandidates = try await stagedCandidates(input)
        var digests: [String: String] = [:]
        for index in items.indices {
            try Task.checkCancellation()
            var item = items[index]
            if item.canAnalyze {
                do {
                    if item.photoID != nil {
                        digests[item.id] = Self.resourceSignature(item)
                    } else if let url = item.url, hashCandidates.contains(item.id) {
                        let cached = try await store.loadCleanupState(String.self, key: "hash:" + item.reviewKey)
                        let digest = try cached ?? FingerprintService.fullHash(for: url)
                        try await store.saveCleanupState(digest, key: "hash:" + item.reviewKey)
                        digests[item.id] = digest
                    }
                    if item.kind == .image {
                        let measured = try await measure(item, settings: settings)
                        item.facts = measured.facts
                        item.createdAt = measured.facts.capturedAt ?? item.createdAt
                        images[item.id] = measured
                    } else if let url = item.url {
                        item.facts = try await Self.mediaFacts(url, item: item)
                    }
                } catch is CancellationError { throw CancellationError() } catch {
                    item.analysisError = error.localizedDescription
                }
            }
            Self.applySourceFacts(&item)
            items[index] = item
            if let digest = digests[item.id] { hashes[digest, default: []].append(item) }
            await progress(
                CleanupProgress(String(localized: "Analyzing media"), completed: index + 1, total: items.count))
            await Task.yield()
        }
        var groups = hashes.values.filter { $0.count > 1 }.map {
            Self.group(.duplicates, items: $0, explanation: String(localized: "Exact content match"))
        }
        groups += try await nearMatches(items, images: images)
        groups += Self.timeGroups(items, seconds: settings.similarSeconds)
        groups += Self.burstGroups(items)
        groups += Self.formatGroups(items, images: images)
        return AnalysisResult(generation: UUID(), scopeID: scopeID, settings: settings, items: items, groups: groups)
    }

    private static func resourceSignature(_ item: ReviewItem) -> String? {
        let resources = item.resources
        if resources.count == 1, let digest = resources.first?.hash { return digest }
        guard !resources.isEmpty, resources.allSatisfy({ $0.hash != nil }) else { return nil }
        return resources.map { "\($0.type):\($0.hash ?? "")" }.sorted().joined(separator: "|")
    }

    private func stagedCandidates(_ input: [ReviewItem]) async throws -> Set<String> {
        let groups = Dictionary(grouping: input.filter(\.canAnalyze), by: \.bytes)
        var candidates = Set<String>()
        for group in groups.values where group.count > 1 {
            try Task.checkCancellation()
            let files = group.filter { $0.url != nil }
            if group.contains(where: { $0.photoID != nil }) {
                candidates.formUnion(files.map(\.id))
                continue
            }
            var quick: [String: [String]] = [:]
            for item in files {
                try Task.checkCancellation()
                if let url = item.url {
                    let digest = try FingerprintService.quickHash(for: url, sizeBytes: item.bytes)
                    quick[digest, default: []].append(item.id)
                }
            }
            for matches in quick.values where matches.count > 1 { candidates.formUnion(matches) }
            await Task.yield()
        }
        return candidates
    }

    private func measure(_ item: ReviewItem, settings: CleanupSettings) async throws -> ImageMeasurement {
        let url: URL
        if let file = item.url { url = file } else { url = try await photos.analysisPreview(item) }
        do {
            let measured = try ImageQualityAnalysis.measureImage(
                url, original: item.facts, sensitivity: settings.categorySensitivity)
            if item.photoID != nil { await photos.releaseAnalysisPreview(url) }
            return measured
        } catch {
            if item.photoID != nil { await photos.releaseAnalysisPreview(url) }
            throw error
        }
    }

    public static func candidates(_ tool: CleanupTool, in result: AnalysisResult) -> [ReviewItem] {
        let grouped = Set(result.groups.filter { $0.tool == tool }.flatMap(\.memberIDs))
        return result.items.filter { item in
            switch tool {
            case .duplicates, .similar, .bursts: grouped.contains(item.id)
            case .formatPairs: grouped.contains(item.id) || isCompoundPhoto(item)
            case .blurry: qualityIssue(item, sensitivity: result.settings.blurSensitivity) != nil
            case .large: item.bytes >= Int64(result.settings.largeMegabytes * 1_000_000)
            case .screenshots: item.facts.isScreenshot
            case .screenRecordings: item.facts.isScreenRecording
            case .categories, .imageCompression: item.kind == .image
            case .videoCompression: item.kind == .video
            case .downloads: isDownload(item)
            case .swipe: true
            }
        }
    }

    public static func qualityIssue(_ item: ReviewItem, sensitivity: Int) -> String? {
        qualityIssues(item, sensitivity: sensitivity).first
    }

    public static func qualityIssues(_ item: ReviewItem, sensitivity: Int) -> [String] {
        guard item.kind == .image, item.canAnalyze else { return [] }
        var issues: [String] = []
        if let light = item.facts.luminance, light < 0.12 { issues.append(String(localized: "Too dark")) }
        if let clipped = item.facts.clippedHighlights, clipped > 0.35 {
            issues.append(String(localized: "Overexposed"))
        }
        let thresholds = [0.00025, 0.0006, 0.0012]
        if let sharp = item.facts.sharpness, sharp < thresholds[min(2, max(0, sensitivity))] {
            issues.append(String(localized: "Out of focus"))
        }
        return issues
    }

    public static func isCompoundPhoto(_ item: ReviewItem) -> Bool {
        let types = Set(item.resources.map(\.type))
        return item.photoID != nil && (types.contains(9) || types.contains(4))
    }

    public static func isDownload(_ item: ReviewItem) -> Bool {
        if item.facts.isExportedChatMedia == true { return true }
        let path = item.sourceName.lowercased()
        return ["downloads", "whatsapp", "telegram", "messages export", "chat export"].contains { path.contains($0) }
    }

    public static func timeGroups(_ items: [ReviewItem], seconds: Double) -> [AnalysisGroup] {
        var seen = Set<String>()
        return [false, true].flatMap { modified in
            timeGroups(items, seconds: seconds, modified: modified)
        }.filter { seen.insert($0.id).inserted }
    }

    private static func timeGroups(_ items: [ReviewItem], seconds: Double, modified: Bool) -> [AnalysisGroup] {
        func date(_ item: ReviewItem) -> Date? { modified ? item.modifiedAt : item.createdAt }
        let pools = Dictionary(grouping: items.filter(\.canAnalyze)) { $0.sourceName + $0.kind.rawValue }
        return pools.values.flatMap { pool -> [AnalysisGroup] in
            let ordered = pool.sorted {
                (date($0) ?? .distantPast) < (date($1) ?? .distantPast)
            }
            var groups: [AnalysisGroup] = []
            var batch: [ReviewItem] = []
            for item in ordered {
                if let first = batch.first, let start = date(first),
                    let current = date(item),
                    current.timeIntervalSince(start) > max(1, min(60, seconds)) {
                    if batch.count > 1 {
                        groups.append(
                            group(
                                .similar, items: batch,
                                explanation: modified
                                    ? String(localized: "Modified close together")
                                    : String(localized: "Captured close together")))
                    }
                    batch = []
                }
                if date(item) != nil { batch.append(item) }
            }
            if batch.count > 1 {
                groups.append(
                    group(
                        .similar, items: batch,
                        explanation: modified
                            ? String(localized: "Modified close together")
                            : String(localized: "Captured close together")))
            }
            return groups
        }
    }

    public static func safeSelection(_ proposed: Set<String>, groups: [AnalysisGroup]) -> Set<String> {
        var selected = proposed
        for group in groups where group.memberIDs.allSatisfy({ selected.contains($0) }) {
            selected.remove(group.bestID)
        }
        return selected
    }

    private static func group(
        _ tool: CleanupTool, items: [ReviewItem], explanation: String,
        isVisualMatch: Bool = false
    ) -> AnalysisGroup {
        let ranked = items.sorted { lhs, rhs in
            let left = lhs.facts.sharpness ?? 0
            let right = rhs.facts.sharpness ?? 0
            if left != right { return left > right }
            if tool == .duplicates {
                let pixels = (lhs.facts.width ?? 0) * (lhs.facts.height ?? 0)
                let other = (rhs.facts.width ?? 0) * (rhs.facts.height ?? 0)
                if pixels != other { return pixels > other }
            }
            let date = lhs.createdAt ?? lhs.modifiedAt ?? .distantPast
            let otherDate = rhs.createdAt ?? rhs.modifiedAt ?? .distantPast
            if date != otherDate { return tool == .duplicates ? date > otherDate : date < otherDate }
            return lhs.id < rhs.id
        }
        return AnalysisGroup(
            tool: tool, memberIDs: ranked.map(\.id), bestID: ranked.first?.id ?? "", explanation: explanation,
            isVisualMatch: isVisualMatch)
    }

    private func nearMatches(
        _ items: [ReviewItem], images: [String: ImageMeasurement]
    ) async throws -> [AnalysisGroup] {
        var representatives: [[ReviewItem]] = []
        for item in items where images[item.id] != nil {
            try Task.checkCancellation()
            guard let measurement = images[item.id], let feature = measurement.feature else { continue }
            var found: Int?
            for index in representatives.indices {
                guard let representative = representatives[index].first,
                    let other = images[representative.id], let otherFeature = other.feature,
                    (other.perceptualHash ^ measurement.perceptualHash).nonzeroBitCount <= 12
                else { continue }
                var distance: Float = 0
                try feature.computeDistance(&distance, to: otherFeature)
                if distance <= 0.35 {
                    found = index
                    break
                }
            }
            if let found { representatives[found].append(item) } else { representatives.append([item]) }
            await Task.yield()
        }
        return representatives.filter { $0.count > 1 }.map {
            Self.group(
                .duplicates, items: $0, explanation: String(localized: "Visual near-match. Check before removing"),
                isVisualMatch: true)
        }
    }

    private static func burstGroups(_ items: [ReviewItem]) -> [AnalysisGroup] {
        let members = items.filter { $0.facts.burstIdentifier != nil }
        return Dictionary(grouping: members) { $0.sourceName + ($0.facts.burstIdentifier ?? "") }.values
            .filter { $0.count > 1 }.map { group(.bursts, items: $0, explanation: String(localized: "Burst sequence")) }
    }

}

extension MediaAnalysisService {
    private static func formatGroups(_ items: [ReviewItem], images: [String: ImageMeasurement]) -> [AnalysisGroup] {
        let pools = Dictionary(grouping: items.filter { $0.canAnalyze && $0.url != nil && $0.kind == .image }) {
            $0.sourceName + ($0.url?.deletingPathExtension().lastPathComponent.lowercased() ?? "")
        }
        let stills = pools.values.compactMap { pool -> AnalysisGroup? in
            let extensions = Set(pool.compactMap { $0.url?.pathExtension.lowercased() })
            let raw = !extensions.isDisjoint(with: ["dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2"])
            let jpeg = !extensions.isDisjoint(with: ["jpg", "jpeg"])
            let stillPair = jpeg && (raw || extensions.contains("heic"))
            guard stillPair, pool.count > 1 else { return nil }
            if stillPair {
                guard let first = pool.first, let feature = images[first.id]?.feature else { return nil }
                for item in pool.dropFirst() {
                    guard let other = images[item.id]?.feature else { return nil }
                    var distance: Float = 0
                    guard (try? feature.computeDistance(&distance, to: other)) != nil, distance < 0.35 else {
                        return nil
                    }
                    if let lhs = first.createdAt, let rhs = item.createdAt, abs(lhs.timeIntervalSince(rhs)) > 5 {
                        return nil
                    }
                }
            }
            return group(
                .formatPairs, items: pool,
                explanation: String(localized: "Paired formats. Removing a component loses its editing or motion data")
            )
        }
        return stills + livePhotoGroups(items)
    }

    static func livePhotoGroups(_ items: [ReviewItem]) -> [AnalysisGroup] {
        let eligible = items.filter { $0.canAnalyze && $0.url != nil && $0.facts.contentIdentifier != nil }
        return Dictionary(grouping: eligible) { $0.sourceName + "|" + ($0.facts.contentIdentifier ?? "") }
            .values.compactMap { pool in
                guard pool.count == 2, Set(pool.map(\.kind)) == [.image, .video] else { return nil }
                return group(
                    .formatPairs, items: pool,
                    explanation: String(localized: "Live Photo pair. Removing a component loses motion or still data"))
            }
    }

    private static func applySourceFacts(_ item: inout ReviewItem) {
        let name = item.name.lowercased()
        item.facts.isScreenshot =
            item.facts.isScreenshot
            || (item.kind == .image && ["screenshot", "screen shot"].contains { name.hasPrefix($0) })
        item.facts.isScreenRecording =
            item.facts.isScreenRecording
            || (item.kind == .video && ["screen recording", "screenrecording"].contains { name.hasPrefix($0) })
        if item.facts.burstIdentifier == nil,
            name.range(of: #"(?:burst|sequence)[_-]?\d+"#, options: .regularExpression) != nil {
            let stem = name.replacingOccurrences(of: #"[_-]?\d+(?=\.[^.]+$)"#, with: "", options: .regularExpression)
            let day = Int((item.createdAt ?? item.modifiedAt ?? .distantPast).timeIntervalSince1970 / 60)
            item.facts.burstIdentifier = "\(stem):\(day)"
        }
        if item.facts.category == .other, isDownload(item) { item.facts.category = .savedFromApps }
    }

    private static func mediaFacts(_ url: URL, item: ReviewItem) async throws -> MediaFacts {
        var facts = item.facts
        if item.kind == .pdf { facts.pageCount = PDFDocument(url: url)?.pageCount }
        if item.kind == .video || item.kind == .audio {
            let asset = AVURLAsset(url: url)
            facts.duration = try await asset.load(.duration).seconds
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                let size = try await track.load(.naturalSize)
                facts.width = Int(size.width)
                facts.height = Int(size.height)
            }
            let metadata = try await asset.load(.metadata)
            for entry in metadata where entry.identifier == .quickTimeMetadataContentIdentifier {
                facts.contentIdentifier = try await entry.load(.stringValue)
            }
        }
        return facts
    }

}
