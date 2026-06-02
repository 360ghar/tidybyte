import SwiftUI

/// Identifies which burst group (and which frame) a full-screen preview was
/// opened from, so the preview's Delete action can target the right group.
private struct BurstPreviewContext: Identifiable {
    let id: String
    let groupId: String
    let assets: [AssetSummary]
    let startIndex: Int
}

struct BurstCleanerView: View {
    @State private var viewModel = BurstCleanerViewModel()
    @State private var showAutoCleanConfirm = false
    @State private var showDeleteConfirm = false
    @State private var preview: BurstPreviewContext?
    private let photoService = PhotoLibraryService()

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.groups.isEmpty {
                EmptyStateView(
                    icon: "square.stack.3d.up",
                    title: "No Burst Photos",
                    message: "You don't have any burst photo groups."
                )
            } else {
                contentView
            }
        }
        .navigationTitle("Burst Photos")
        .alert("Auto-Clean All Bursts", isPresented: $showAutoCleanConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.deletableCount) Photos", role: .destructive) {
                Task {
                    await viewModel.autoCleanAll()
                    HapticHelper.notification(.success)
                }
            }
        } message: {
            Text("This will keep only the best photo from each burst group and delete all others. This action cannot be undone.")
        }
        .alert("Delete Selected Burst Photos", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.selectedCount) Photos", role: .destructive) {
                Task {
                    await viewModel.deleteSelected()
                    HapticHelper.notification(.success)
                }
            }
        } message: {
            Text("This will delete the currently selected burst frames and keep your chosen best photos.")
        }
        .alert("Burst Cleaner Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("Retry") {
                viewModel.errorMessage = nil
                Task { await viewModel.deleteSelected() }
            }
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Bursts Cleaned", isPresented: .init(
            get: { viewModel.statusMessage != nil },
            set: { if !$0 { viewModel.statusMessage = nil } }
        )) {
            Button("OK") { viewModel.statusMessage = nil }
        } message: {
            Text(viewModel.statusMessage ?? "")
        }
        .fullScreenCover(item: $preview) { context in
            MediaPreviewView(
                assets: context.assets,
                startIndex: context.startIndex,
                photoService: photoService,
                onDelete: { await viewModel.deleteAsset(id: $0.id, fromGroup: context.groupId) }
            )
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        List {
            ForEach(0..<6, id: \.self) { _ in
                SkeletonRow()
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }

    // MARK: - Content View

    private var contentView: some View {
        VStack(spacing: 0) {
            // Summary header
            summaryHeader
                .fadeSlideIn()

            List {
                ForEach(Array(viewModel.groups.enumerated()), id: \.element.id) { index, group in
                    burstGroupRow(group)
                        .fadeSlideIn(delay: Double(index) * 0.03)
                }
            }
            .listStyle(.plain)
            .pullToRefresh { await viewModel.refresh() }

            // Bottom action bar
            ActionBarView {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("\(viewModel.deletableCount) removable")
                        .font(.caption.bold())
                    Text("\(viewModel.selectedCount) selected · \(viewModel.selectedSavingsBytes.formattedFileSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: Spacing.sm) {
                    Button {
                        HapticHelper.impact(.light)
                        showDeleteConfirm = true
                    } label: {
                        Text("Delete Selected")
                            .font(.headline)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background(Color.destructive)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    }
                    .scaleOnPress()
                    .disabled(viewModel.selectedCount == 0)

                    Button {
                        HapticHelper.impact(.light)
                        showAutoCleanConfirm = true
                    } label: {
                        Text("Auto-Clean")
                            .font(.headline)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background(.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    }
                    .scaleOnPress()
                }
            }
        }
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("\(viewModel.groups.count) burst groups")
                    .font(.headline)
                Text("\(viewModel.totalBurstCount) total · \(viewModel.deletableCount) removable · \(viewModel.savingsBytes.formattedFileSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "square.stack.3d.up")
                .font(.title2)
                .foregroundStyle(.blue.opacity(0.7))
        }
        .glassCard()
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Burst Group Row

    private func burstGroupRow(_ group: BurstGroup) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("\(group.assets.count) frames")
                    .font(.subheadline.bold())
                Spacer()
                if let date = group.assets.first?.creationDate {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(group.assets) { asset in
                        VStack(spacing: Spacing.xs) {
                            ZStack(alignment: .topTrailing) {
                                Button {
                                    preview = BurstPreviewContext(
                                        id: asset.id,
                                        groupId: group.id,
                                        assets: group.assets,
                                        startIndex: group.assets.firstIndex { $0.id == asset.id } ?? 0
                                    )
                                } label: {
                                    AsyncThumbnailView(assetId: asset.id, photoService: photoService)
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: CornerRadius.small)
                                                .stroke(asset.id == group.bestAssetId ? Color.green : Color.clear, lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Preview burst frame")

                                if asset.id == group.bestAssetId {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                        .padding(Spacing.xs)
                                } else {
                                    Button {
                                        HapticHelper.selection()
                                        viewModel.toggleSelection(asset.id)
                                    } label: {
                                        Image(systemName: viewModel.selectedForDeletion.contains(asset.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.caption)
                                            .foregroundStyle(viewModel.selectedForDeletion.contains(asset.id) ? .red : .white)
                                            .padding(Spacing.xs)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(viewModel.selectedForDeletion.contains(asset.id) ? "Keep burst frame" : "Select burst frame for deletion")
                                    .accessibilityAddTraits(viewModel.selectedForDeletion.contains(asset.id) ? [.isButton, .isSelected] : .isButton)
                                }
                            }

                            Button {
                                HapticHelper.selection()
                                viewModel.setBest(assetId: asset.id, in: group.id)
                            } label: {
                                Text(asset.id == group.bestAssetId ? "Best" : "Keep Best")
                                    .font(.caption2.bold())
                                    .foregroundStyle(asset.id == group.bestAssetId ? .green : .blue)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(asset.id == group.bestAssetId ? "Best frame" : "Keep this frame as best")

                            if asset.isFavorite {
                                Image(systemName: "heart.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}
