import SwiftUI

struct SimilarGroupDetailView: View {
    @State private var group: SimilarGroup
    @Binding var selectedForDeletion: Set<String>
    let onSetBest: (String, String) -> Void

    @State private var currentPage = 0
    @State private var albumNames: [String: [String]] = [:]

    private let photoService = PhotoLibraryService()

    init(
        group: SimilarGroup,
        selectedForDeletion: Binding<Set<String>>,
        onSetBest: @escaping (String, String) -> Void
    ) {
        _group = State(initialValue: group)
        _selectedForDeletion = selectedForDeletion
        self.onSetBest = onSetBest
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(Array(group.assets.enumerated()), id: \.element.id) { index, asset in
                    assetDetailCard(asset)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(maxHeight: .infinity)

            ActionBarView {
                let currentAsset = group.assets[safe: currentPage]
                let isBest = currentAsset?.id == group.bestAssetId

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("\(currentPage + 1) of \(group.assets.count)")
                        .font(.caption.bold())
                    Text(isBest ? "Keeping this · \(group.bestReason.rawValue)" : "Recommended: \(group.bestReason.rawValue)")
                        .font(.caption)
                        .foregroundStyle(isBest ? .green : .secondary)
                }

                Spacer()

                if let currentAsset, !isBest {
                    Button {
                        HapticHelper.selection()
                        let oldBest = group.bestAssetId
                        group = SimilarGroup(
                            id: group.id,
                            assets: group.assets,
                            bestAssetId: currentAsset.id,
                            qualityScores: group.qualityScores,
                            bestReason: .userChosen
                        )
                        selectedForDeletion.remove(currentAsset.id)
                        if oldBest != currentAsset.id {
                            selectedForDeletion.insert(oldBest)
                        }
                        onSetBest(currentAsset.id, group.id)
                    } label: {
                        Text("Keep This Best")
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
                        if selectedForDeletion.contains(currentAsset.id) {
                            selectedForDeletion.remove(currentAsset.id)
                        } else {
                            selectedForDeletion.insert(currentAsset.id)
                        }
                    } label: {
                        Text(selectedForDeletion.contains(currentAsset.id) ? "Keep This" : "Mark Delete")
                            .font(.headline)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background(selectedForDeletion.contains(currentAsset.id) ? .gray : .red)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    }
                    .scaleOnPress()
                }
            }
        }
        .navigationTitle("Review Group")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            for asset in group.assets {
                let names = await photoService.albumsContaining(assetId: asset.id)
                albumNames[asset.id] = names
            }
        }
    }

    private func assetDetailCard(_ asset: AssetSummary) -> some View {
        VStack(spacing: 0) {
            AsyncThumbnailView(
                assetId: asset.id,
                photoService: photoService,
                targetSize: CGSize(width: 600, height: 600)
            )
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .overlay(alignment: .topTrailing) {
                if asset.id == group.bestAssetId {
                    statusPill(icon: "star.fill", text: group.bestReason.rawValue, color: .green)
                } else if selectedForDeletion.contains(asset.id) {
                    statusPill(icon: "trash.fill", text: "Delete", color: .red)
                }
            }
            .padding(.horizontal, Spacing.lg)

            VStack(spacing: Spacing.sm) {
                metadataRow("Resolution", value: asset.resolution)
                metadataRow("File Size", value: asset.formattedFileSize)
                if let date = asset.creationDate {
                    metadataRow("Date", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                if let names = albumNames[asset.id], !names.isEmpty {
                    metadataRow("Albums", value: names.joined(separator: ", "))
                } else {
                    metadataRow("Albums", value: "None")
                }
                if let quality = group.qualityScores[asset.id] {
                    qualitySection(quality)
                }
            }
            .glassCard()
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
        }
    }

    @ViewBuilder
    private func qualitySection(_ quality: AssetQuality) -> some View {
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

    private func statusPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.bold())
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(color.opacity(0.85))
        .clipShape(Capsule())
        .padding(Spacing.sm)
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .multilineTextAlignment(.trailing)
        }
    }
}
