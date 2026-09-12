import SwiftUI
import StoreKit

struct DuplicateFinderView: View {
    @State private var viewModel = DuplicateFinderViewModel()
    @State private var showDeleteConfirm = false
    @State private var selectedGroup: DuplicateGroup?
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
                ToolbarItem(placement: .topBarLeading) {
                    SelectAllToolbarButton(
                        allSelected: viewModel.allSelectedForDeletion,
                        selectAll: { viewModel.selectAllForDeletion() },
                        deselectAll: { viewModel.deselectAllForDeletion() }
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // C8: this deletes the current SELECTION (keepers excluded),
                    // so the label says what it does instead of "Delete All".
                    Button("Delete Selected") {
                        HapticHelper.impact(.light)
                        showDeleteConfirm = true
                    }
                    .foregroundStyle(.red)
                    .disabled(viewModel.isDeleting || viewModel.selectedForDeletion.isEmpty)
                }
            }
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
            Text("This will permanently delete \(viewModel.selectedForDeletion.count) duplicate items.")
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
            tint: .blue,
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
                            Button { selectedGroup = group } label: {
                                duplicateGroupRow(group)
                            }
                            .buttonStyle(.plain)
                            // DUP-04a: delete just this group's non-best assets.
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    HapticHelper.impact(.light)
                                    Task { await viewModel.delete(group: group) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .fadeSlideIn(delay: Double(index) * 0.03)
                        }
                    }
                    .listStyle(.plain)
                    .pullToRefresh { viewModel.startScan() }

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
            HStack {
                Text("\(group.assets.count) items")
                    .font(.subheadline.bold())
                Text(group.type == .exact ? "Exact" : "Visual")
                    .font(.caption2.bold())
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(group.type == .exact ? Color.red.opacity(0.2) : Color.orange.opacity(0.2))
                    .clipShape(Capsule())
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(group.assets) { asset in
                        ZStack(alignment: .topTrailing) {
                            AsyncThumbnailView(assetId: asset.id, photoService: photoService)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                            if asset.id == group.bestAssetId {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                                    .padding(Spacing.xs)
                            } else if viewModel.selectedForDeletion.contains(asset.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .padding(Spacing.xs)
                            }
                        }
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
