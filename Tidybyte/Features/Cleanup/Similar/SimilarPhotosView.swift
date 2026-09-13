import SwiftUI
import StoreKit

struct SimilarPhotosView: View {
    @State private var viewModel = SimilarPhotosViewModel()
    @State private var showDeleteConfirm = false
    @State private var selectedGroup: SimilarGroup?
    @Environment(\.requestReview) private var requestReview
    @State private var isCelebrating = false
    // Shared with the Settings mirror on the same key — @AppStorage is the single
    // source of truth, so a change in either screen is observed by the other (the
    // value is invisible to @Observable if held on the VM, hence it lives here).
    @AppStorage(AppPreferences.Key.similarPhotoTimeWindow) private var timeWindow: Double = 5.0
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
                    title: "Similar Photos",
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
        .navigationTitle("Similar Photos")
        .happyPathCelebration(isPresented: $isCelebrating, statLine: "removed \(viewModel.deletedCount) similar photos")
        .toolbar {
            if viewModel.scanState == .completed && !viewModel.groups.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    // Back to the idle screen, where the time-window slider lives —
                    // otherwise there's no way to change the window once results show.
                    Button {
                        HapticHelper.impact(.light)
                        viewModel.scanState = .idle
                    } label: {
                        Label("New Scan", systemImage: "arrow.counterclockwise")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // C8: deletes the current selection (keepers excluded).
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
                group: SimilarComparison(group),
                selectedForDeletion: $viewModel.selectedForDeletion,
                onSetBest: { assetId, groupId in
                    viewModel.setBest(assetId: assetId, in: groupId)
                },
                descriptor: .similar,
                extraDetail: { asset in
                    if let quality = group.qualityScores[asset.id] {
                        ComparisonQualitySection(quality: quality)
                    }
                }
            )
            .navigationTitle("Review Group")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Delete Similar Photos", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.selectedForDeletion.count) Items", role: .destructive) {
                Task {
                    await viewModel.deleteSelected()
                    // DUP-04d: only celebrate an actual deletion.
                    if viewModel.errorMessage == nil && viewModel.deletedCount > 0 {
                        HappyPathReporter.fire(isCelebrating: $isCelebrating, requestReview: requestReview)
                    }
                }
            }
        } message: {
            Text("The best photo from each group will be kept.")
        }
        // DUP-02: leaving the screen must stop the scan.
        .onDisappear {
            viewModel.cancelScan()
        }
    }

    // MARK: - Idle View

    private var idleView: some View {
        ToolIdleView(
            icon: "square.on.square",
            tint: .blue,
            title: "Find Similar Photos",
            message: "Groups photos taken within \(Int(timeWindow)) seconds of each other.",
            primaryTitle: "Start Scan",
            primaryHint: "Scans your library for photos taken close together",
            primaryAction: {
                HapticHelper.impact(.light)
                // DUP-02: route through the VM-held task so the scan is
                // cancellable and re-entry is guarded.
                viewModel.startScan(timeWindow: timeWindow)
            }
        ) {
            VStack(spacing: Spacing.sm) {
                Text("Time Window: \(Int(timeWindow))s")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Slider(value: $timeWindow, in: 1...60, step: 1)
                    .onChange(of: timeWindow) {
                        HapticHelper.selection()
                    }
            }
            .glassCard()
        }
        .fadeSlideIn()
    }

    // MARK: - Scanning View

    private func scanningView(progress: Float) -> some View {
        ToolScanningView(
            icon: "magnifyingglass",
            tint: .blue,
            title: "Grouping similar photos...",
            progress: progress,
            onCancel: {
                HapticHelper.impact(.light)
                viewModel.cancelScan()
            }
        )
        .fadeSlideIn()
    }

    // MARK: - Results View

    private var resultsView: some View {
        Group {
            if viewModel.groups.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "No Similar Photos Found",
                    message: "Your library looks clean!",
                    iconColor: .green,
                    actionTitle: "Scan Again"
                ) {
                    HapticHelper.impact(.light)
                    viewModel.scanState = .idle
                }
            } else {
                VStack(spacing: 0) {
                    List {
                        // Summary card
                        Section {
                            HStack(spacing: Spacing.md) {
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text("\(viewModel.groups.count) groups found")
                                        .font(.headline)
                                    Text("\(viewModel.totalDuplicateCount) extras · \(viewModel.selectedSavingsBytes.formattedFileSize) selected")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "square.on.square")
                                    .font(.title2)
                                    .foregroundStyle(.blue.opacity(0.7))
                            }
                            .glassCard()
                            .listRowInsets(EdgeInsets(top: Spacing.sm, leading: Spacing.lg, bottom: Spacing.sm, trailing: Spacing.lg))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .fadeSlideIn()

                        // Groups
                        ForEach(Array(viewModel.groups.enumerated()), id: \.element.id) { index, group in
                            groupRow(group)
                                .fadeSlideIn(delay: Double(index) * 0.03)
                        }
                    }
                    .listStyle(.plain)
                    .pullToRefresh { viewModel.startScan(timeWindow: timeWindow) }

                    // Bottom action bar
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
                                    Text("Delete Selected")
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

    // MARK: - Group Row

    private func groupRow(_ group: SimilarGroup) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("\(group.assets.count) photos")
                    .font(.subheadline.bold())
                Spacer()
                if let date = group.assets.first?.creationDate {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    selectedGroup = group
                } label: {
                    Label("Review", systemImage: "chevron.right")
                        .font(.caption.bold())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Review similar photo group")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(group.assets) { asset in
                        let quality = group.qualityScores[asset.id]
                        VStack(spacing: Spacing.xs) {
                            ZStack(alignment: .topTrailing) {
                                AsyncThumbnailView(assetId: asset.id, photoService: photoService)
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CornerRadius.small)
                                            .stroke(asset.id == group.bestAssetId ? Color.green : Color.clear, lineWidth: 2)
                                    )
                                    .overlay(alignment: .bottom) {
                                        if let quality {
                                            sharpnessBar(quality.sharpness)
                                                .padding(.horizontal, Spacing.xs)
                                                .padding(.bottom, Spacing.xs)
                                                .accessibilityLabel("Sharpness \(Int((quality.sharpness * 100).rounded())) percent")
                                        }
                                    }
                                    .overlay(alignment: .topLeading) {
                                        if let icon = exposureIcon(quality) {
                                            Image(systemName: icon)
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(3)
                                                .background(Color.black.opacity(0.5), in: Circle())
                                                .padding(Spacing.xs)
                                        }
                                        // C10: warn that this photo's quality was
                                        // scored from a low-res iCloud copy.
                                        if quality?.usedFallback == true {
                                            Image(systemName: "icloud.and.arrow.down")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(3)
                                                .background(Color.orange.opacity(0.8), in: Circle())
                                                .padding(Spacing.xs)
                                                .offset(x: 22)
                                                .accessibilityLabel("Quality analyzed from a low-resolution copy")
                                        }
                                    }

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
                                            .foregroundStyle(viewModel.selectedForDeletion.contains(asset.id) ? .red : .white)
                                            .padding(Spacing.xs)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(viewModel.selectedForDeletion.contains(asset.id) ? "Keep photo" : "Select photo for deletion")
                                    .accessibilityAddTraits(viewModel.selectedForDeletion.contains(asset.id) ? [.isButton, .isSelected] : .isButton)
                                }
                            }

                            if asset.id == group.bestAssetId {
                                Label(group.bestReason.rawValue, systemImage: "star.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, Spacing.xs)
                                    .padding(.vertical, 2)
                                    .background(Color.success, in: Capsule())
                                    .accessibilityLabel("Recommended to keep: \(group.bestReason.rawValue)")
                            } else {
                                Button {
                                    HapticHelper.selection()
                                    viewModel.setBest(assetId: asset.id, in: group.id)
                                } label: {
                                    Text("Keep This")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Keep this photo as best")
                            }
                        }
                        .frame(width: 80)
                    }
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Quality chips

    private func sharpnessBar(_ value: Float) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.black.opacity(0.35))
            Capsule()
                .fill(sharpnessColor(value))
                .frame(width: max(3, 64 * CGFloat(min(1, max(0, value)))))
        }
        .frame(width: 64, height: 4)
    }

    private func sharpnessColor(_ value: Float) -> Color {
        if value >= 0.6 { return .success }
        if value >= 0.4 { return .warning }
        return .destructive
    }

    /// Returns an SF Symbol only when the photo is flagged dark/bright — nothing
    /// for well-exposed photos, so the common case stays uncluttered.
    private func exposureIcon(_ quality: AssetQuality?) -> String? {
        guard let quality else { return nil }
        if quality.isTooDark { return "moon.fill" }
        if quality.isOverexposed { return "sun.max.fill" }
        return nil
    }
}
