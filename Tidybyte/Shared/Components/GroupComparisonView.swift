import SwiftUI

/// Minimal contract a group-comparison pager needs. Both the Duplicates and the
/// Similar detail screens are the same TabView(.page) shell; only the keeper
/// bookkeeping and the per-screen copy differ, so the shared pager below talks
/// to this protocol and each screen supplies an adapter plus a descriptor.
protocol ComparisonGroup: Identifiable, Sendable where ID == String {
    var assets: [AssetSummary] { get }
    var bestAssetId: String { get }
    /// Local keeper-swap rebuild (mirrors the old per-screen swap math: the
    /// VM-side `setBest` mutation stays on each VM — this only refreshes the
    /// pager's own copy so pills/status flip immediately).
    func withBest(_ assetId: String) -> Self
}

/// Adapter over `DuplicateGroup` (declared in DuplicateDetectionService.swift).
struct DuplicateComparison: ComparisonGroup {
    let base: DuplicateGroup
    var id: String { base.id }
    var assets: [AssetSummary] { base.assets }
    var bestAssetId: String { base.bestAssetId }

    init(_ base: DuplicateGroup) {
        self.base = base
    }

    func withBest(_ assetId: String) -> Self {
        Self(DuplicateGroup(id: base.id, assets: base.assets, bestAssetId: assetId, type: base.type))
    }
}

/// Adapter over `SimilarGroup` (declared in SimilarPhotosViewModel.swift).
struct SimilarComparison: ComparisonGroup {
    let base: SimilarGroup
    var id: String { base.id }
    var assets: [AssetSummary] { base.assets }
    var bestAssetId: String { base.bestAssetId }

    init(_ base: SimilarGroup) {
        self.base = base
    }

    func withBest(_ assetId: String) -> Self {
        Self(SimilarGroup(
            id: base.id,
            assets: base.assets,
            bestAssetId: assetId,
            qualityScores: base.qualityScores,
            bestReason: .userChosen
        ))
    }
}

/// Per-screen copy/behavior knobs. Closures take the current group (so the
/// keeper pill/status follow a keeper swap) and run on the main thread only,
/// hence plain closure types with no Sendable requirement.
struct ComparisonDescriptor<G: ComparisonGroup> {
    /// Text in the green keeper pill ("Best" vs the best-reason label).
    let bestPillText: (G) -> String
    /// Second status line under the page counter; nil hides it.
    let statusText: (G, Bool) -> String?
    let statusColor: (G, Bool) -> Color
    let keepBestTitle: String
    let keepTitle: String
    /// "Mark for Deletion" (Duplicates) vs "Mark Delete" (Similar) — preserved.
    let deleteTitle: String
    /// Pill background opacity: 0.8 (Duplicates) vs 0.85 (Similar) — preserved.
    let pillOpacity: Double
}

extension ComparisonDescriptor where G == DuplicateComparison {
    static var duplicates: Self {
        Self(
            bestPillText: { _ in "Best" },
            statusText: { _, isBest in isBest ? "Best quality" : nil },
            statusColor: { _, _ in .green },
            keepBestTitle: "Keep This Best",
            keepTitle: "Keep This",
            deleteTitle: "Mark for Deletion",
            pillOpacity: 0.8
        )
    }
}

extension ComparisonDescriptor where G == SimilarComparison {
    static var similar: Self {
        Self(
            bestPillText: { $0.base.bestReason.rawValue },
            statusText: { group, isBest in
                isBest
                    ? "Keeping this · \(group.base.bestReason.rawValue)"
                    : "Recommended: \(group.base.bestReason.rawValue)"
            },
            statusColor: { _, isBest in isBest ? .green : .secondary },
            keepBestTitle: "Keep This Best",
            keepTitle: "Keep This",
            deleteTitle: "Mark Delete",
            pillOpacity: 0.85
        )
    }
}

/// Shared group-comparison pager. Title-free body: the call site sets
/// `.navigationTitle` (Duplicates: "Compare", Similar: "Review Group").
/// `Detail` is a generic slot (not AnyView) so the Similar quality section can
/// be injected with no type erasure; Duplicates uses `EmptyView`.
struct GroupComparisonView<G: ComparisonGroup, Detail: View>: View {
    @State private var group: G
    @Binding var selectedForDeletion: Set<String>
    let onSetBest: (String, String) -> Void
    let descriptor: ComparisonDescriptor<G>
    let extraDetail: (AssetSummary) -> Detail

    @State private var currentPage = 0
    @State private var albumNames: [String: [String]] = [:]

    private let photoService = PhotoLibraryService.shared

    init(
        group: G,
        selectedForDeletion: Binding<Set<String>>,
        onSetBest: @escaping (String, String) -> Void,
        descriptor: ComparisonDescriptor<G>,
        @ViewBuilder extraDetail: @escaping (AssetSummary) -> Detail
    ) {
        _group = State(initialValue: group)
        _selectedForDeletion = selectedForDeletion
        self.onSetBest = onSetBest
        self.descriptor = descriptor
        self.extraDetail = extraDetail
    }

    var body: some View {
        VStack(spacing: 0) {
            // Paged image viewer
            TabView(selection: $currentPage) {
                ForEach(Array(group.assets.enumerated()), id: \.element.id) { index, asset in
                    assetDetailCard(asset)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(maxHeight: .infinity)

            // Bottom actions
            ActionBarView {
                let current = group.assets[safe: currentPage]
                let isBest = current?.id == group.bestAssetId

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("\(currentPage + 1) of \(group.assets.count)")
                        .font(.caption.bold())
                    if let status = descriptor.statusText(group, isBest) {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(descriptor.statusColor(group, isBest))
                    }
                }

                Spacer()

                if let current, !isBest {
                    Button {
                        HapticHelper.selection()
                        let oldBest = group.bestAssetId
                        group = group.withBest(current.id)
                        selectedForDeletion.remove(current.id)
                        if oldBest != current.id {
                            selectedForDeletion.insert(oldBest)
                        }
                        onSetBest(current.id, group.id)
                    } label: {
                        Text(descriptor.keepBestTitle)
                            .font(.headline)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background(.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    }
                    .scaleOnPress()

                    Button {
                        HapticHelper.selection()
                        if selectedForDeletion.contains(current.id) {
                            selectedForDeletion.remove(current.id)
                        } else {
                            selectedForDeletion.insert(current.id)
                        }
                    } label: {
                        Text(selectedForDeletion.contains(current.id) ? descriptor.keepTitle : descriptor.deleteTitle)
                            .font(.headline)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background(selectedForDeletion.contains(current.id) ? .gray : .red)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    }
                    .scaleOnPress()
                }
            }
        }
        .task {
            // DUP-06: one batched pass over user albums instead of a per-asset
            // album fetch (which was O(assets × albums) blocking PhotoKit calls).
            albumNames = await AlbumMembershipLoader.membership(for: Set(group.assets.map(\.id)))
        }
    }

    private func assetDetailCard(_ asset: AssetSummary) -> some View {
        VStack(spacing: 0) {
            // Image
            AsyncThumbnailView(
                assetId: asset.id,
                photoService: photoService,
                targetSize: CGSize(width: 600, height: 600)
            )
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .overlay(alignment: .topTrailing) {
                if asset.id == group.bestAssetId {
                    statusPill(icon: "star.fill", text: descriptor.bestPillText(group), color: .green)
                } else if selectedForDeletion.contains(asset.id) {
                    statusPill(icon: "trash.fill", text: "Delete", color: .red)
                }
            }
            .padding(.horizontal, Spacing.lg)

            // Metadata
            VStack(spacing: Spacing.sm) {
                MetadataRow(label: "Resolution", value: asset.resolution)
                MetadataRow(label: "File Size", value: asset.displaySize)
                if let date = asset.creationDate {
                    MetadataRow(label: "Date", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                if let names = albumNames[asset.id], !names.isEmpty {
                    MetadataRow(label: "Albums", value: names.joined(separator: ", "))
                } else {
                    MetadataRow(label: "Albums", value: "None")
                }
                extraDetail(asset)
            }
            .glassCard()
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
        }
    }

    private func statusPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.bold())
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(color.opacity(descriptor.pillOpacity))
        .clipShape(Capsule())
        .padding(Spacing.sm)
    }
}

extension GroupComparisonView where Detail == EmptyView {
    init(
        group: G,
        selectedForDeletion: Binding<Set<String>>,
        onSetBest: @escaping (String, String) -> Void,
        descriptor: ComparisonDescriptor<G>
    ) {
        self.init(
            group: group,
            selectedForDeletion: selectedForDeletion,
            onSetBest: onSetBest,
            descriptor: descriptor,
            extraDetail: { _ in EmptyView() }
        )
    }
}

/// Sharpness bar + exposure row shown under Similar metadata — moved verbatim
/// from the old Similar detail screen (helpers included, no VM references).
struct ComparisonQualitySection: View {
    let quality: AssetQuality

    var body: some View {
        Group {
            Divider()
            HStack {
                Text("Sharpness")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.cardBorder)
                    Capsule()
                        .fill(sharpnessColor(quality.sharpness))
                        .frame(width: max(4, 80 * CGFloat(min(1, max(0, quality.sharpness)))))
                }
                .frame(width: 80, height: 5)
                Text("\(Int((quality.sharpness * 100).rounded()))%")
                    .font(.caption.bold().monospacedDigit())
            }
            HStack {
                Text("Exposure")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(exposureLabel(quality))
                    .font(.caption.bold())
                    .foregroundStyle(exposureColor(quality))
            }
        }
    }

    private func sharpnessColor(_ value: Float) -> Color {
        if value >= 0.6 { return .success }
        if value >= 0.4 { return .warning }
        return .destructive
    }

    private func exposureLabel(_ quality: AssetQuality) -> String {
        if quality.isTooDark { return "Too dark" }
        if quality.isOverexposed { return "Overexposed" }
        return "Good"
    }

    private func exposureColor(_ quality: AssetQuality) -> Color {
        (quality.isTooDark || quality.isOverexposed) ? .warning : .success
    }
}
