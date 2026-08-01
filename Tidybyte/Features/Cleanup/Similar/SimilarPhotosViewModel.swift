import SwiftUI
import Vision

/// Per-photo quality signals computed once during the scan (reusing the CGImage
/// already decoded for the Vision feature print) and carried on the group so the
/// keeper recommendation, the "why" badge, and the per-thumbnail chips can all be
/// derived without re-analyzing images.
struct AssetQuality: Sendable, Hashable {
    let assetId: String
    let sharpness: Float        // 1 - blurScore; higher = sharper
    let luminance: Float        // 0...1 mean luminance
    let isTooDark: Bool
    let isOverexposed: Bool
    let isBlurry: Bool
}

/// The single dominant reason a photo was recommended as the keeper, surfaced to
/// the user so the auto-pick isn't a black box.
enum BestReason: String, Sendable {
    case sharpest = "Sharpest"
    case bestExposed = "Best exposed"
    case favorite = "Favorite"
    case highestRes = "Highest res"
    case mostRecent = "Most recent"
    case bestOverall = "Best overall"
    case userChosen = "Your choice"
}

struct SimilarGroup: Identifiable, Hashable, Sendable {
    let id: String
    let assets: [AssetSummary]
    var bestAssetId: String
    var qualityScores: [String: AssetQuality] = [:]
    var bestReason: BestReason = .bestOverall
}

@Observable
@MainActor
final class SimilarPhotosViewModel {
    var groups: [SimilarGroup] = []
    var scanState: ScanState = .idle
    var selectedForDeletion: Set<String> = []
    var errorMessage: String?
    var isDeleting = false
    /// DUP-04/DUP-09: how many items the last delete actually removed, so the
    /// view can gate the success haptic on a non-zero result.
    var deletedCount = 0

    /// Vision feature-print distance threshold used to confirm that photos in the
    /// same time cluster actually look alike. Lower = stricter.
    private static let visualSimilarityThreshold: Float = 0.7

    /// DUP-11: a single time cluster is split into index chunks of at most this
    /// many photos before the O(n²) Vision subgrouping. nil-creationDate photos
    /// all sort to `.distantPast` and would otherwise collapse into one giant
    /// cluster; chunking keeps chronological order and bounds the pairing work.
    private static let maxClusterSize = 60

    private let photoService = PhotoLibraryService()
    private let visionService = VisionAnalysisService()
    /// DUP-02: the scan is held in a cancellable task so leaving the screen or
    /// tapping Cancel actually stops it, and re-entry can be guarded.
    private var scanTask: Task<Void, Never>?

    var totalDuplicateCount: Int {
        groups.reduce(0) { $0 + $1.assets.count - 1 }
    }

    var totalSavingsBytes: Int64 {
        groups.reduce(Int64(0)) { total, group in
            let nonBest = group.assets.filter { $0.id != group.bestAssetId }
            return total + nonBest.reduce(Int64(0)) { $0 + $1.fileSize }
        }
    }

    var selectedSavingsBytes: Int64 {
        groups.reduce(Int64(0)) { total, group in
            total + group.assets.filter { selectedForDeletion.contains($0.id) }
                .reduce(0) { subtotal, asset in subtotal + asset.fileSize }
        }
    }

    /// `timeWindow` (seconds) is owned by the view as shared `@AppStorage` on
    /// `AppPreferences.Key.similarPhotoTimeWindow`, so the Similar Photos slider
    /// and the Settings mirror are a single source of truth. It's passed in (by
    /// value) at scan start so changing the slider mid-scan can't produce
    /// inconsistent grouping.
    func scan(timeWindow: Double) async {
        scanState = .scanning(0)
        selectedForDeletion.removeAll()
        errorMessage = nil
        deletedCount = 0

        let capturedTimeWindow = timeWindow
        let threshold = Self.visualSimilarityThreshold

        let photos = await photoService.fetchAllPhotos()
            .sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }

        // Phase 1: cluster photos taken close together in time (cheap, in-memory).
        // DUP-11: oversized clusters (e.g. many nil-creationDate photos sorting
        // to .distantPast) are index-chunked so the visual phase stays bounded.
        var clusters: [[AssetSummary]] = []
        var currentCluster: [AssetSummary] = []
        for photo in photos {
            if Task.isCancelled { scanState = .idle; return }
            if let last = currentCluster.last {
                let interval = (photo.creationDate ?? .distantPast)
                    .timeIntervalSince(last.creationDate ?? .distantPast)
                if interval <= capturedTimeWindow {
                    currentCluster.append(photo)
                } else {
                    if currentCluster.count >= 2 { clusters.append(contentsOf: cappedClusters(currentCluster)) }
                    currentCluster = [photo]
                }
            } else {
                currentCluster = [photo]
            }
        }
        if currentCluster.count >= 2 { clusters.append(contentsOf: cappedClusters(currentCluster)) }

        // Phase 2: within each time cluster, keep only subgroups that are actually
        // visually similar (via Vision feature prints), so shots of different
        // subjects taken close together aren't lumped together.
        var foundGroups: [SimilarGroup] = []
        let totalPhotosInClusters = clusters.reduce(0) { $0 + $1.count }
        var processedPhotos = 0
        for cluster in clusters {
            if Task.isCancelled { scanState = .idle; return }
            let (subgroups, quality) = await visuallyCoherentSubgroups(from: cluster, threshold: threshold)
            for subgroup in subgroups {
                // First-wins so a duplicated id can't trap the scan.
                let subgroupQuality = subgroup.reduce(into: [String: AssetQuality]()) { result, asset in
                    if let score = quality[asset.id], result[asset.id] == nil {
                        result[asset.id] = score
                    }
                }
                let pick = selectBest(from: subgroup, quality: subgroupQuality)
                foundGroups.append(SimilarGroup(
                    id: UUID().uuidString,
                    assets: subgroup,
                    bestAssetId: pick.asset.id,
                    qualityScores: subgroupQuality,
                    bestReason: pick.reason
                ))
            }
            processedPhotos += cluster.count
            let progress = totalPhotosInClusters > 0 ? Float(processedPhotos) / Float(totalPhotosInClusters) : 1.0
            scanState = .scanning(progress)
        }

        if Task.isCancelled {
            scanState = .idle
            return
        }

        groups = foundGroups
        scanState = .completed

        selectNonBestAssets()
    }

    // MARK: - Scan lifecycle (DUP-02)

    func startScan(timeWindow: Double) {
        guard scanTask == nil else { return }
        scanTask = Task { [weak self] in
            await self?.scan(timeWindow: timeWindow)
            self?.scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        if case .scanning = scanState {
            scanState = .idle
        }
    }

    /// DUP-11: split an oversized time cluster into index chunks of at most
    /// `maxClusterSize` photos. Chronological order is preserved; the heuristic
    /// is purely a work bound for the Vision pairing, not a similarity signal.
    private func cappedClusters(_ cluster: [AssetSummary]) -> [[AssetSummary]] {
        guard cluster.count > Self.maxClusterSize else { return [cluster] }
        return stride(from: 0, to: cluster.count, by: Self.maxClusterSize).map {
            Array(cluster[$0..<min($0 + Self.maxClusterSize, cluster.count)])
        }
    }

    /// Splits a time-based cluster into subgroups whose members are visually
    /// similar according to Vision feature-print distance. Returns only subgroups
    /// with two or more members.
    private func visuallyCoherentSubgroups(
        from cluster: [AssetSummary],
        threshold: Float
    ) async -> (subgroups: [[AssetSummary]], quality: [String: AssetQuality]) {
        // A pair is the common case for a time cluster; only generate feature prints
        // when there's something to compare.
        guard cluster.count >= 2 else { return ([], [:]) }

        var prints: [(asset: AssetSummary, print: FeaturePrint)] = []
        var quality: [String: AssetQuality] = [:]
        for asset in cluster {
            if Task.isCancelled { return ([], quality) }
            guard let cgImage = await loadCGImage(for: asset.id),
                  let featurePrint = await visionService.generateFeaturePrint(image: cgImage) else {
                continue
            }
            // Reuse the SAME CGImage already decoded for the feature print — no
            // second image load — to also score blur and exposure for the keeper
            // recommendation and the UI quality chips.
            let blur = await visionService.analyzeBlurriness(image: cgImage, assetId: asset.id)
            let exposure = await visionService.analyzeExposure(image: cgImage, assetId: asset.id)
            quality[asset.id] = AssetQuality(
                assetId: asset.id,
                sharpness: 1 - blur.blurScore,
                luminance: exposure.meanLuminance,
                isTooDark: exposure.isTooDark,
                isOverexposed: exposure.isOverexposed,
                isBlurry: blur.isBlurry
            )
            prints.append((asset, featurePrint))
            await Task.yield()
        }

        var visited = Set<String>()
        var subgroups: [[AssetSummary]] = []
        for i in prints.indices {
            guard !visited.contains(prints[i].asset.id) else { continue }
            var group = [prints[i].asset]
            visited.insert(prints[i].asset.id)
            for j in (i + 1)..<prints.count {
                if Task.isCancelled { return (subgroups, quality) }
                guard !visited.contains(prints[j].asset.id) else { continue }
                let distance = await visionService.computeDistance(between: prints[i].print, and: prints[j].print)
                if distance < threshold {
                    group.append(prints[j].asset)
                    visited.insert(prints[j].asset.id)
                }
            }
            if group.count >= 2 { subgroups.append(group) }
        }
        return (subgroups, quality)
    }

    /// DUP-08: score quality on a sharp, exactly-sized, network-off analysis
    /// image (nil for iCloud-only assets) and fall back to the fast 300px
    /// thumbnail only when the original isn't on this device — matches
    /// BlurryPhotosViewModel, so the keeper recommendation isn't computed from
    /// degraded thumbnails.
    private func loadCGImage(for assetId: String) async -> CGImage? {
        if let analysisImage = await photoService.loadAnalysisImage(for: assetId, targetSize: CGSize(width: 512, height: 512)) {
            return analysisImage.cgImage
        }
        let thumbnail = await photoService.loadThumbnail(for: assetId, size: CGSize(width: 300, height: 300))
        return thumbnail?.cgImage
    }

    func deleteSelected() async {
        guard !selectedForDeletion.isEmpty, !isDeleting else { return }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await photoService.deleteAssets(identifiers: Array(selectedForDeletion))
            deletedCount = selectedForDeletion.count
            let deleted = selectedForDeletion
            groups = groups.compactMap { group in
                let remaining = group.assets.filter { !deleted.contains($0.id) }
                guard remaining.count > 1 else { return nil }
                let slimQuality = group.qualityScores.filter { key, _ in
                    remaining.contains { $0.id == key }
                }
                let bestAssetId: String
                let bestReason: BestReason
                if remaining.contains(where: { $0.id == group.bestAssetId }) {
                    bestAssetId = group.bestAssetId
                    bestReason = group.bestReason
                } else {
                    let pick = selectBest(from: remaining, quality: slimQuality)
                    bestAssetId = pick.asset.id
                    bestReason = pick.reason
                }
                return SimilarGroup(
                    id: group.id,
                    assets: remaining,
                    bestAssetId: bestAssetId,
                    qualityScores: slimQuality,
                    bestReason: bestReason
                )
            }
            selectNonBestAssets()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleSelection(_ assetId: String) {
        var state = SelectionState(ids: selectedForDeletion)
        state.toggle(assetId)
        selectedForDeletion = state.ids
    }

    func setBest(assetId: String, in groupId: String) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        let oldBest = groups[index].bestAssetId
        groups[index].bestAssetId = assetId
        groups[index].bestReason = .userChosen
        var state = SelectionState(ids: selectedForDeletion)
        state.setBest(newBest: assetId, oldBest: oldBest)
        selectedForDeletion = state.ids
    }

    private func selectNonBestAssets() {
        var state = SelectionState()
        for group in groups {
            state.selectNonBest(assets: group.assets, bestAssetId: group.bestAssetId)
        }
        selectedForDeletion = state.ids
    }

    /// Quality-first keeper selection. Combines sharpness, exposure, resolution,
    /// favorite, and recency into a 0...1 composite (each signal normalized
    /// *within the group*) and reports the dominant reason for the pick so the UI
    /// can explain it. Photos within `epsilon` of the top score fall back to the
    /// deterministic metadata ladder so the winner is stable.
    private func selectBest(
        from assets: [AssetSummary],
        quality: [String: AssetQuality]
    ) -> (asset: AssetSummary, reason: BestReason) {
        guard assets.count > 1 else { return (assets[0], .bestOverall) }

        let maxPixels = max(1, assets.map { $0.pixelWidth * $0.pixelHeight }.max() ?? 1)
        // Rank each asset by recency (oldest = 0 … newest = count-1), tie-broken by
        // id so photos that share a creationDate (bursts/imports) get distinct,
        // stable ranks instead of all collapsing to the same firstIndex. Precomputed
        // once into a dictionary rather than an O(n) firstIndex lookup per asset.
        let recencyRank: [String: Int] = {
            let ordered = assets.sorted {
                let l = $0.creationDate ?? .distantPast
                let r = $1.creationDate ?? .distantPast
                return l == r ? $0.id < $1.id : l < r
            }
            // First-wins so a duplicated id can't trap the scan; earliest
            // rank is the one the sort produced.
            return ordered.enumerated().reduce(into: [String: Int]()) { result, entry in
                if result[entry.element.id] == nil {
                    result[entry.element.id] = entry.offset
                }
            }
        }()

        func sharpness(_ asset: AssetSummary) -> Float { quality[asset.id]?.sharpness ?? 0.5 }
        func exposureScore(_ asset: AssetSummary) -> Float {
            guard let q = quality[asset.id] else { return 0.5 }
            var score = max(0, 1 - 2 * abs(q.luminance - 0.5))
            if q.isTooDark || q.isOverexposed { score *= 0.4 }
            return score
        }
        func resolutionScore(_ asset: AssetSummary) -> Float {
            Float(asset.pixelWidth * asset.pixelHeight) / Float(maxPixels)
        }
        func recencyScore(_ asset: AssetSummary) -> Float {
            guard assets.count > 1 else { return 1 }
            let rank = recencyRank[asset.id] ?? 0
            return Float(rank) / Float(assets.count - 1)
        }
        func composite(_ asset: AssetSummary) -> Float {
            0.35 * sharpness(asset)
            + 0.25 * exposureScore(asset)
            + 0.20 * resolutionScore(asset)
            + 0.10 * (asset.isFavorite ? 1 : 0)
            + 0.10 * recencyScore(asset)
        }

        let scored = assets.map { (asset: $0, score: composite($0)) }
        let bestScore = scored.map(\.score).max() ?? 0
        let epsilon: Float = 0.02
        let contenders = scored.filter { bestScore - $0.score <= epsilon }.map(\.asset)
        let winner = BestAssetSelector.bestByMetadata(from: contenders) ?? assets[0]

        // Attribute the win to the signal where the winner most out-scored the
        // rest, so the displayed badge matches the math.
        let others = assets.filter { $0.id != winner.id }
        let reason: BestReason
        if winner.isFavorite && !others.contains(where: { $0.isFavorite }) {
            reason = .favorite
        } else if others.isEmpty {
            reason = .bestOverall
        } else {
            func margin(_ value: (AssetSummary) -> Float) -> Float {
                value(winner) - (others.map(value).max() ?? 0)
            }
            let weighted: [(reason: BestReason, value: Float)] = [
                (.sharpest, 0.35 * margin(sharpness)),
                (.bestExposed, 0.25 * margin(exposureScore)),
                (.highestRes, 0.20 * margin(resolutionScore)),
                (.mostRecent, 0.10 * margin(recencyScore))
            ]
            reason = weighted.max { $0.value < $1.value }
                .flatMap { $0.value > 0.01 ? $0.reason : nil } ?? .bestOverall
        }
        return (winner, reason)
    }
}
