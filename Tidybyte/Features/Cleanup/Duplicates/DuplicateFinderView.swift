import SwiftUI
import StoreKit

struct DuplicateFinderView: View {
    @State private var viewModel = DuplicateFinderViewModel()
    @State private var showDeleteConfirm = false
    @State private var selectedGroup: DuplicateGroup?
    @State private var preview: GroupPreviewContext?
    @Environment(\.requestReview) private var requestReview
    @State private var isCelebrating = false
    private let photoService = PhotoLibraryService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Non-modal error surface. Replaces the OK-only alert: an alert
            // interrupts the task and costs a tap to dismiss, and it left the
            // screen exactly as it already was.
            if let message = viewModel.errorMessage {
                ToolErrorBanner(
                    message: message,
                    title: "Duplicates",
                    onDismiss: { viewModel.errorMessage = nil }
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
            }

            Group {
                switch viewModel.scanState {
                case .idle:
                    idleView
                        .transition(.stateTransition)
                case .scanning(let progress):
                    scanningView(progress: progress)
                        .transition(.stateTransition)
                case .completed:
                    resultsView
                        .transition(.stateTransition)
                }
            }
        }
        .animation(.reduceMotionAware(.spring(response: 0.4, dampingFraction: 0.85), reduceMotion: reduceMotion), value: viewModel.scanState)
        .navigationTitle("Duplicates")
        .happyPathCelebration(isPresented: $isCelebrating, statLine: "removed \(viewModel.deletedCount) duplicates")
        .toolbar {
            if viewModel.scanState == .completed && !viewModel.allGroups.isEmpty {
                // DUP-05: a scan type / library change needs a fresh scan — return
                // to the idle screen instead of being stuck on stale results.
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        HapticHelper.impact(.light)
                        viewModel.scanState = .idle
                    } label: {
                        Label("New Scan", systemImage: "arrow.counterclockwise")
                    }
                }
                // DUP-04c: select/deselect every asset across all groups.
                // Delete lives in the bottom bar only.
                ToolbarItem(placement: .topBarTrailing) {
                    SelectAllToolbarButton(
                        allSelected: viewModel.allSelectedForDeletion,
                        selectAll: { viewModel.selectAllForDeletion() },
                        deselectAll: { viewModel.deselectAllForDeletion() }
                    )
                }
            }
        }
        .fullScreenCover(item: $preview) { context in
            MediaPreviewView(assets: context.assets, startIndex: context.startIndex, photoService: photoService)
        }
        .navigationDestination(item: $selectedGroup) { group in
            GroupComparisonView(
                group: DuplicateComparison(group),
                selectedForDeletion: $viewModel.selectedForDeletion,
                onSetBest: { assetId, groupId in
                    viewModel.setBest(assetId: assetId, in: groupId)
                },
                descriptor: .duplicates
            )
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Delete \(viewModel.selectedForDeletion.count) Items", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.selectedForDeletion.count) Items", role: .destructive) {
                Task {
                    await viewModel.deleteSelected()
                    // DUP-04d: only celebrate an actual deletion (the guard can
                    // still return early on an empty selection).
                    if viewModel.errorMessage == nil && viewModel.deletedCount > 0 {
                        HappyPathReporter.fire(isCelebrating: $isCelebrating, requestReview: requestReview)
                    }
                }
            }
        } message: {
            Text("This will delete \(viewModel.selectedForDeletion.count) duplicate items. \(CleanupDeletion.recoverableNote)")
        }
        // DUP-02: leaving the screen must stop the scan (it would otherwise run
        // to completion in the background and re-enter on return).
        .onDisappear {
            viewModel.cancelScan()
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        ToolIdleView(
            icon: "doc.on.doc",
            tint: .red,
            title: "Find Duplicate Photos",
            message: "Scan your library for exact and visually similar duplicates.",
            primaryTitle: "Start Scan",
            primaryHint: "Scans your whole library for duplicates",
            primaryAction: {
                HapticHelper.impact(.light)
                // DUP-02: route through the VM-held task so the scan is
                // cancellable and re-entry is guarded.
                viewModel.startScan()
            }
        ) {
            Picker("Scan Type", selection: $viewModel.scanType) {
                ForEach(DuplicateScanType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .fadeSlideIn()
    }

    // MARK: - Scanning

    private func scanningView(progress: Float) -> some View {
        ToolScanningView(
            icon: "magnifyingglass",
            tint: CleanupTool.duplicates.color,
            title: "Scanning for duplicates...",
            progress: progress,
            onCancel: {
                HapticHelper.impact(.light)
                viewModel.cancelScan()
            }
        )
        .fadeSlideIn()
    }

    // MARK: - Results

    private var resultsView: some View {
        Group {
            if viewModel.allGroups.isEmpty {
                EmptyStateView(icon: "checkmark.circle", title: "No Duplicates Found", message: "Your photo library is clean!", iconColor: .green, actionTitle: "Scan Again") {
                    viewModel.scanState = .idle
                }
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("\(viewModel.allGroups.count) groups")
                                .font(.headline)
                            Text("\(viewModel.totalDuplicateCount) duplicates · \(viewModel.selectedSavingsBytes.formattedFileSize) selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            // DUP-03: explain why iCloud-only photos are absent
                            // from an exact scan.
                            if viewModel.skippedICloudCount > 0 {
                                Text("\(viewModel.skippedICloudCount) iCloud-only photo\(viewModel.skippedICloudCount == 1 ? "" : "s") skipped (not on this device)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            // Only while no visual group has a pick yet.
                            if viewModel.allGroups.contains(where: { $0.type == .visual }),
                               !viewModel.allGroups.contains(where: { $0.type == .visual && !viewModel.checkedIds(in: $0).isEmpty }) {
                                Text("Visual matches are not selected. Open a group to pick, or tap Select All.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "doc.on.doc")
                            .font(.title2)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .glassCard()
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .fadeSlideIn()

                    List {
                        ForEach(Array(viewModel.allGroups.enumerated()), id: \.element.id) { index, group in
                            duplicateGroupRow(group)
                            // DUP-04a: delete just this group's checked assets. No
                            // full swipe: a delete needs a deliberate tap.
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                let checked = viewModel.checkedIds(in: group).count
                                if checked > 0 {
                                    Button(role: .destructive) {
                                        HapticHelper.impact(.light)
                                        Task { await viewModel.delete(group: group) }
                                    } label: {
                                        Label("Delete \(checked)", systemImage: "trash")
                                    }
                                }
                            }
                            .fadeSlideIn(delay: Double(index) * 0.03)
                        }
                    }
                    .listStyle(.plain)

                    // DUP-04b: delete-selected bar, mirroring Similar Photos.
                    if !viewModel.selectedForDeletion.isEmpty {
                        ActionBarView {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("\(viewModel.selectedForDeletion.count) selected")
                                    .font(.caption.bold())
                                Text(viewModel.selectedSavingsBytes.formattedFileSize)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if viewModel.isDeleting {
                                // DUP-09: in-flight feedback instead of a dead button.
                                ProgressView()
                                    .padding(.horizontal, Spacing.xxl)
                                    .padding(.vertical, Spacing.sm)
                            } else {
                                Button {
                                    HapticHelper.impact(.light)
                                    showDeleteConfirm = true
                                } label: {
                                    Text("Delete Selected (\(viewModel.selectedForDeletion.count))")
                                        .font(.headline)
                                        .padding(.horizontal, Spacing.xxl)
                                        .padding(.vertical, Spacing.sm)
                                        .background(Color.destructive)
                                        .foregroundStyle(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                                }
                                .scaleOnPress()
                            }
                        }
                    }
                }
            }
        }
    }

    private func duplicateGroupRow(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // The header opens Compare; each thumbnail opens a preview; the
            // circle marks for deletion. Same pattern as Similar and Bursts.
            Button { selectedGroup = group } label: {
                HStack {
                    Text("\(group.assets.count) \(group.type == .exact ? "exact copies" : "look alike")")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("Compare")
                        .font(.caption.bold())
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the side-by-side comparison")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    ForEach(Array(group.assets.enumerated()), id: \.element.id) { index, asset in
                        let isKeeper = asset.id == group.bestAssetId
                        VStack(spacing: Spacing.xs) {
                            AsyncThumbnailView(assetId: asset.id, photoService: photoService)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                                .overlay(alignment: .bottomLeading) {
                                    if asset.isFavorite {
                                        FavoriteMark().padding(Spacing.xs)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    preview = GroupPreviewContext(assets: group.assets, startIndex: index)
                                }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel("Preview photo, \(asset.displaySize)")
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

            Text(group.assets.map(\.displaySize).joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Spacing.xs)
    }
}
