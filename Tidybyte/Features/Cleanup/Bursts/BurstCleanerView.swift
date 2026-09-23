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
        .toolbar {
            if !viewModel.groups.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    SelectAllToolbarButton(
                        allSelected: viewModel.allNonBestSelected,
                        selectAll: { viewModel.selectAllNonBest() },
                        deselectAll: { viewModel.deselectAll() }
                    )
                }
            }
        }
        .happyPathCelebration(isPresented: $isCelebrating, statLine: celebrationStatLine)
        .toast($toast)
        .alert("Auto-Clean All Bursts", isPresented: $showAutoCleanConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.deletableCount) Photos", role: .destructive) {
                Task {
                    // Celebrate only what really left the library: a declined
                    // iOS prompt or a failure deletes nothing.
                    let removed = await viewModel.autoCleanAll()
                    guard removed > 0, viewModel.errorMessage == nil else { return }
                    HappyPathReporter.fire(
                        isCelebrating: $isCelebrating,
                        statLine: $celebrationStatLine,
                        line: "cleaned \(removed) burst photos",
                        requestReview: requestReview
                    )
                }
            }
        } message: {
            Text("This keeps the starred frame of each burst and deletes the rest. Favorites are kept. \(CleanupDeletion.recoverableNote)")
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
            Text("This will delete the selected burst frames and keep your chosen best photos. \(CleanupDeletion.recoverableNote)")
        }
        // Non-modal error surface. The retry is preserved from the alert it
        // replaces: a failed burst delete leaves the selection intact, so
        // re-running the same delete is the correct recovery.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = viewModel.errorMessage {
                ToolErrorBanner(
                    message: message,
                    title: CleanupTool.bursts.name,
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
                    .disabled(viewModel.deletableCount == 0)
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
                .foregroundStyle(CleanupTool.bursts.color)
        }
        .glassCard()
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Burst Group Row

    /// Why the starred frame is the one kept. Plain text, so the user can
    /// check the choice before Auto-Clean.
    private func keeperReason(for group: BurstGroup) -> String {
        if viewModel.manuallySetBest.contains(group.id) { return "Kept: your choice" }
        guard let best = group.assets.first(where: { $0.id == group.bestAssetId }) else { return "" }
        switch best.burstPick {
        case .user: return "Kept: your pick in Photos"
        case .iPhone: return "Kept: iPhone's pick"
        case .none: return best.isFavorite ? "Kept: favorite" : "Kept: last frame"
        }
    }

    private func burstGroupRow(_ group: BurstGroup) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("\(group.assets.count) frames")
                    .font(.subheadline.bold())
                Text(keeperReason(for: group))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        let isKeeper = asset.id == group.bestAssetId
                        VStack(spacing: Spacing.xs) {
                            AsyncThumbnailView(assetId: asset.id, photoService: photoService)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.small)
                                        .stroke(isKeeper ? Color.success : Color.clear, lineWidth: 2)
                                )
                                .overlay(alignment: .bottomLeading) {
                                    if asset.isFavorite {
                                        FavoriteMark().padding(Spacing.xs)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    preview = BurstPreviewContext(id: asset.id, groupId: group.id)
                                }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel("Preview burst frame")
                                .overlay(alignment: .topTrailing) {
                                    if !isKeeper {
                                        DeleteToggle(isMarked: viewModel.selectedForDeletion.contains(asset.id)) {
                                            viewModel.toggleSelection(asset.id)
                                        }
                                        .offset(x: Spacing.xs, y: -Spacing.xs)
                                    }
                                }

                            if isKeeper {
                                KeeperMark()
                                    .frame(minHeight: 44)
                            } else {
                                MakeKeeperButton {
                                    viewModel.setBest(assetId: asset.id, in: group.id)
                                }
                            }
                        }
                        .frame(width: 80)
                    }
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}
