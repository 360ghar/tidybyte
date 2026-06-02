import SwiftUI

struct DuplicateComparisonView: View {
    @State private var group: DuplicateGroup
    @Binding var selectedForDeletion: Set<String>
    let onSetBest: (String, String) -> Void
    @State private var currentPage = 0
    @State private var albumNames: [String: [String]] = [:]

    private let photoService = PhotoLibraryService()

    init(
        group: DuplicateGroup,
        selectedForDeletion: Binding<Set<String>>,
        onSetBest: @escaping (String, String) -> Void
    ) {
        _group = State(initialValue: group)
        _selectedForDeletion = selectedForDeletion
        self.onSetBest = onSetBest
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
                    if isBest {
                        Text("Best quality")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                if let current, !isBest {
                    Button {
                        HapticHelper.selection()
                        let oldBest = group.bestAssetId
                        group = DuplicateGroup(id: group.id, assets: group.assets, bestAssetId: current.id, type: group.type)
                        selectedForDeletion.remove(current.id)
                        if oldBest != current.id {
                            selectedForDeletion.insert(oldBest)
                        }
                        onSetBest(current.id, group.id)
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
                        if selectedForDeletion.contains(current.id) {
                            selectedForDeletion.remove(current.id)
                        } else {
                            selectedForDeletion.insert(current.id)
                        }
                    } label: {
                        Text(selectedForDeletion.contains(current.id) ? "Keep This" : "Mark for Deletion")
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
        .navigationTitle("Compare")
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
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "star.fill")
                        Text("Best")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(.green.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(Spacing.sm)
                } else if selectedForDeletion.contains(asset.id) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "trash.fill")
                        Text("Delete")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(.red.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(Spacing.sm)
                }
            }
            .padding(.horizontal, Spacing.lg)

            // Metadata
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
            }
            .glassCard()
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
        }
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
        }
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
