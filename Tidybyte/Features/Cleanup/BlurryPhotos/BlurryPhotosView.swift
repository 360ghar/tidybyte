import SwiftUI
import SwiftData

struct BlurryPhotosView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = BlurryPhotosViewModel()
    @Environment(LibraryChangeMonitor.self) private var libraryMonitor
    @State private var showDeleteConfirm = false
    @State private var isCelebrating = false
    @State private var selectedSwipeRoute: SwipeSessionRoute?
    @State private var previewPhoto: AnalyzedPhoto?
    @State private var pendingSwipeReview = false
    @State private var cellToDelete: AnalyzedPhoto?

    private let photoService = PhotoLibraryService.shared

    private let columns = ResponsiveGrid.photo()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Non-modal error surface. Replaces the OK-only alert: an alert
            // interrupts the task and costs a tap to dismiss, and it left the
            // screen exactly as it already was.
            if let message = viewModel.errorMessage {
                ToolErrorBanner(
                    message: message,
                    title: "Photo Quality",
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
        .navigationTitle(CleanupTool.blurry.name)
        // Items deleted elsewhere (Swipe Review, the Photos app) leave the
        // list when the library changes, instead of lingering as blanks.
        .task(id: libraryMonitor.generation) {
            await viewModel.pruneDeleted()
        }
        .happyPathCelebration(isPresented: $isCelebrating, statLine: "cleared \(viewModel.deletedCount) blurry photos")
        .onDisappear {
            // D-01: a scan left running after the user leaves the screen would
            // keep consuming CPU (and PhotoKit calls) in the background.
            viewModel.cancelScan()
        }
        .toolbar {
            if viewModel.scanState == .completed {
                if !viewModel.filteredPhotos.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        SelectAllToolbarButton(
                            allSelected: viewModel.allVisibleSelected,
                            selectAll: { viewModel.selectAll() },
                            deselectAll: { viewModel.deselectAll() }
                        )
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if !viewModel.filteredPhotos.isEmpty {
                            Button {
                                HapticHelper.impact(.light)
                                let ids = Set(viewModel.filteredPhotos.map(\.id))
                                startSwipeReview(with: .customAssetIds(ids))
                            } label: {
                                Label("Review with Swipe", systemImage: "hand.draw")
                            }
                        }
                        Button {
                            HapticHelper.impact(.light)
                            viewModel.scanState = .idle
                        } label: {
                            Label("New Scan", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More actions")
                }
            }
        }
        .navigationDestination(item: $selectedSwipeRoute) { route in
            SwipeSessionHostView(
                route: route,
                photoService: photoService,
                modelContext: modelContext
            )
        }
        .alert("Delete Photos", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.totalSelectedCount) Photos", role: .destructive) {
                Task {
                    await viewModel.deleteSelected()
                    // C12: success feedback, gated on an actual deletion.
                    if viewModel.errorMessage == nil && viewModel.deletedCount > 0 {
                        HappyPathReporter.fire(isCelebrating: $isCelebrating)
                    }
                }
            }
        } message: {
            Text(CleanupDeletion.recoverableNote)
        }
        .alert("Delete Photo", isPresented: .init(
            get: { cellToDelete != nil },
            set: { if !$0 { cellToDelete = nil } }
        ), presenting: cellToDelete) { photo in
            Button("Cancel", role: .cancel) { cellToDelete = nil }
            Button("Delete", role: .destructive) {
                let id = photo.id
                cellToDelete = nil
                Task { await viewModel.delete(assetId: id) }
            }
        } message: { _ in
            Text(CleanupDeletion.recoverableNote)
        }
        .fullScreenCover(item: $previewPhoto, onDismiss: {
            if pendingSwipeReview {
                pendingSwipeReview = false
                let ids = Set(viewModel.filteredPhotos.map(\.id))
                startSwipeReview(with: .customAssetIds(ids))
            }
        }) { photo in
            MediaPreviewView(
                assets: viewModel.filteredPhotos.map(\.asset),
                startIndex: viewModel.filteredPhotos.firstIndex { $0.id == photo.id } ?? 0,
                photoService: photoService,
                onDelete: { await viewModel.delete(assetId: $0.id) },
                accessory: AccessoryAction(title: "Review with Swipe", systemImage: "hand.draw") {
                    pendingSwipeReview = true
                }
            )
        }
    }

    private func startSwipeReview(with filter: SwipeFilter) {
        selectedSwipeRoute = SwipeSessionRoute(filter: filter)
    }

    // MARK: - Idle View

    private var idleView: some View {
        ToolIdleView(
            icon: "camera.metering.unknown",
            tint: CleanupTool.blurry.color,
            title: "Detect Low-Quality Photos",
            message: "Find blurry, too dark, and overexposed photos.",
            primaryTitle: "Start Analysis",
            primaryHint: "Scans your library for out-of-focus and poorly lit photos",
            primaryAction: {
                HapticHelper.impact(.light)
                viewModel.startScan()
            }
        )
        .fadeSlideIn()
    }

    // MARK: - Scanning View

    private func scanningView(progress: Float) -> some View {
        ToolScanningView(
            icon: "magnifyingglass",
            tint: CleanupTool.blurry.color,
            title: "Analyzing photos...",
            progress: progress,
            detail: "\(viewModel.analyzedPhotos.count) issues found",
            onCancel: {
                HapticHelper.impact(.light)
                viewModel.cancelScan()
            }
        )
    }

    // MARK: - Results View

    private var resultsView: some View {
        VStack(spacing: 0) {
            // Tab bar
            Picker("Category", selection: $viewModel.activeTab) {
                Text("Blurry (\(viewModel.blurryCount))").tag(BlurryTab.blurry)
                Text("Dark (\(viewModel.darkCount))").tag(BlurryTab.tooDark)
                Text("Bright (\(viewModel.overexposedCount))").tag(BlurryTab.overexposed)
                if viewModel.supportsLensSmudge {
                    Text("Lens Smudge (\(viewModel.smudgeCount))").tag(BlurryTab.lensSmudge)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .readableWidth()

            if viewModel.filteredPhotos.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "All Clear",
                    message: "No issues found in this category.",
                    iconColor: .green,
                    actionTitle: "Scan Again"
                ) {
                    viewModel.startScan()
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Spacing.xs) {
                        ForEach(viewModel.filteredPhotos) { photo in
                            photoCell(photo)
                        }
                    }
                }
            }

            // Outside the list branch: picks on other tabs stay reachable
            // even when this tab is empty.
            if !viewModel.selectedIds.isEmpty {
                ActionBarView {
                    Text(viewModel.selectedOnOtherTabs > 0 ? "\(viewModel.selectedIds.count) selected (\(viewModel.selectedOnOtherTabs) on other tabs) \u{00B7} \(viewModel.selectedSize.formattedFileSize)" : "\(viewModel.selectedIds.count) selected \u{00B7} \(viewModel.selectedSize.formattedFileSize)")
                        .font(.caption)
                    if viewModel.isDeleting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.headline)
                    }
                    .disabled(viewModel.isDeleting)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if viewModel.skippedAnalysisCount > 0 || viewModel.skippedSmudgeCount > 0 {
                Text("\(viewModel.skippedAnalysisCount) photos had no local analysis image. Lens analysis skipped \(viewModel.skippedSmudgeCount) additional photos.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, Spacing.lg)
            }
            if #available(iOS 26, *), !viewModel.supportsLensSmudge {
                Text("Lens smudge analysis is unavailable on this device.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            // D-04: tell the user why their library may look smaller than the
            // full photo count.
            if viewModel.skippedScreenshotCount > 0 {
                Text("\(viewModel.skippedScreenshotCount) screenshots skipped \u{00B7} covered by the Screenshots tool")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.xs)
            }
        }
    }

    // MARK: - Photo Cell

    private func photoCell(_ photo: AnalyzedPhoto) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    AsyncThumbnailView(assetId: photo.id, photoService: photoService)
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Spacing.xs))

            // Score indicator
            HStack(spacing: Spacing.xs) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                        Rectangle()
                            .fill(scoreColor(for: viewModel.activeTab))
                            .frame(width: geo.size.width * CGFloat(scoreValue(for: photo, tab: viewModel.activeTab)))
                    }
                }
                .frame(width: 40, height: 4)
                .clipShape(Capsule())
            }
            .padding(Spacing.sm)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(scoreLabel(for: viewModel.activeTab))
            .accessibilityValue("\(Int((scoreValue(for: photo, tab: viewModel.activeTab) * 100).rounded())) percent")

            // Always-visible selection checkbox. Tapping it (de)selects; tapping
            // anywhere else on the cell opens the preview.
            VStack {
                HStack {
                    Spacer()
                    SelectToggle(isSelected: viewModel.selectedIds.contains(photo.id), itemName: "photo") {
                        viewModel.toggleSelection(photo.id)
                    }
                }
                Spacer()
            }
        }
        .overlay {
            if viewModel.selectedIds.contains(photo.id) {
                RoundedRectangle(cornerRadius: Spacing.xs)
                    .strokeBorder(Color.blue, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            previewPhoto = photo
        }
        .contextMenu {
            Button {
                previewPhoto = photo
            } label: {
                Label("Preview", systemImage: "eye")
            }
            Button(role: .destructive) {
                cellToDelete = photo
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func scoreLabel(for tab: BlurryTab) -> String {
        switch tab {
        case .blurry: "Blur"
        case .tooDark: "Darkness"
        case .overexposed: "Brightness"
        case .lensSmudge: "Lens smudge confidence"
        }
    }

    private func scoreColor(for tab: BlurryTab) -> Color {
        switch tab {
        case .blurry: return .orange
        case .tooDark: return .purple
        case .overexposed: return .yellow
        case .lensSmudge: return .pink
        }
    }

    private func scoreValue(for photo: AnalyzedPhoto, tab: BlurryTab) -> Float {
        switch tab {
        case .blurry:
            return photo.blurScore
        case .tooDark:
            return max(0, min(1, 1 - photo.luminance))
        case .overexposed:
            return photo.luminance
        case .lensSmudge:
            return photo.smudgeConfidence ?? 0
        }
    }
}
