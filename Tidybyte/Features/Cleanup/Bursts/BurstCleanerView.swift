import SwiftUI
import StoreKit

/// Identifies which burst group (and which frame) a full-screen preview was
/// opened from. The preview resolves its assets *live* from the view model on
/// presentation (LF-04), so in-preview deletes re-render against the updated
/// group instead of a frozen snapshot.
private struct BurstPreviewContext: Identifiable {
    let id: String
    let groupId: String
}

struct BurstCleanerView: View {
    @State private var viewModel = BurstCleanerViewModel()
    @State private var showAutoCleanConfirm = false
    @State private var showDeleteConfirm = false
    @State private var preview: BurstPreviewContext?
    @Environment(\.requestReview) private var requestReview
    // statLine is captured at success time: deletableCount/selectedCount are
    // pre-delete values that reset once the action lands.
    @State private var isCelebrating = false
    @State private var celebrationStatLine: String?
    @State private var toast: ToastMessage?
    private let photoService = PhotoLibraryService.shared

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.groups.isEmpty {
                EmptyStateView(
                    icon: "square.stack.3d.up",
                    title: "No Burst Photos",
                    message: "You don't have any burst photo groups.",
                    actionTitle: "Refresh",
                    action: { Task { await viewModel.refresh() } }
                )
            } else {
                contentView
            }
        }
        .navigationTitle("Burst Photos")
        .happyPathCelebration(isPresented: $isCelebrating, statLine: celebrationStatLine)
        .toast($toast)
        .alert("Auto-Clean All Bursts", isPresented: $showAutoCleanConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.deletableCount) Photos", role: .destructive) {
                let count = viewModel.deletableCount
                Task {
                    await viewModel.autoCleanAll()
                    // The Auto-Clean trigger has no disabled-at-zero guard, so
                    // a 0-removable confirm lands here as an error-free no-op
                    // — never celebrate or count that as a happy path.
                    guard count > 0, viewModel.errorMessage == nil else { return }
                    HappyPathReporter.fire(
                        isCelebrating: $isCelebrating,
                        statLine: $celebrationStatLine,
                        line: "cleaned \(count) burst photos",
                        requestReview: requestReview
                    )
                }
            }
        } message: {
            Text("This will keep only the best photo from each burst group and delete all others. This action cannot be undone.")
        }
        .alert("Delete Selected Burst Photos", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.selectedCount) Photos", role: .destructive) {
                let count = viewModel.selectedCount
                Task {
                    await viewModel.deleteSelected()
                    // Same no-op rule: a selection emptied before the confirm
                    // is not a success (defense in depth — the trigger is
                    // disabled at zero).
                    guard count > 0, viewModel.errorMessage == nil else { return }
                    HappyPathReporter.fire(
                        isCelebrating: $isCelebrating,
                        statLine: $celebrationStatLine,
                        line: "cleared \(count) burst frames",
                        requestReview: requestReview
                    )
                }
            }
        } message: {
            Text("This will delete the currently selected burst frames and keep your chosen best photos.")
        }
        // Non-modal error surface. The retry is preserved from the alert it
        // replaces: a failed burst delete leaves the selection intact, so
        // re-running the same delete is the correct recovery.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = viewModel.errorMessage {
                ToolErrorBanner(
                    message: message,
                    title: "Bursts",
                    onRetry: {
                        viewModel.errorMessage = nil
                        Task { await viewModel.deleteSelected() }
                    },
                    onDismiss: { viewModel.errorMessage = nil }
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
            }
        }
        // Transient success note, not a modal: the celebration already covers
        // the win, and this only explains why collapsed groups left the list.
        // Clearing the view-model message keeps it one-shot across redraws.
        .onChange(of: viewModel.statusMessage) { _, newValue in
            guard let newValue else { return }
            toast = ToastMessage(text: newValue, systemImage: "checkmark.circle")
            viewModel.statusMessage = nil
        }
        .fullScreenCover(item: $preview) { context in
            // Resolve the group's assets live so an in-preview delete re-renders
            // the pager against the updated frames (LF-04).
            if let group = viewModel.groups.first(where: { $0.id == context.groupId }) {
                MediaPreviewView(
                    assets: group.assets,
                    startIndex: group.assets.firstIndex { $0.id == context.id } ?? 0,
                    photoService: photoService,
                    onDelete: { await viewModel.deleteAsset(id: $0.id, fromGroup: context.groupId) }
                )
            }
        }
        // If the previewed group collapses away (delete down to a single frame),
        // dismiss the cover instead of showing a dead pager (LF-04).
        .onChange(of: viewModel.groups.map(\.id)) { _, newGroupIds in
            if let preview, !newGroupIds.contains(preview.groupId) {
                self.preview = nil
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        ToolLoadingView { ToolSkeletonList() }
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
                                        groupId: group.id
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
