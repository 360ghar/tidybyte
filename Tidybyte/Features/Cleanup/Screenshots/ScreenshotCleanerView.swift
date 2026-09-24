import SwiftUI
import SwiftData

struct ScreenshotCleanerView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ScreenshotCleanerViewModel()
    @Environment(LibraryChangeMonitor.self) private var libraryMonitor
    @State private var showDeleteConfirm = false
    @State private var isCelebrating = false
    @State private var selectedSwipeRoute: SwipeSessionRoute?
    @State private var previewAsset: AssetSummary?
    @State private var pendingSwipeReview = false
    @State private var cellToDelete: AssetSummary?

    private let photoService = PhotoLibraryService.shared

    private let columns = ResponsiveGrid.photo()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if viewModel.isLoading {
                // D-01: the fetch runs inside a cancellable task, so this is the
                // one loading state that keeps a Cancel.
                ToolLoadingView(onCancel: {
                    HapticHelper.impact(.light)
                    viewModel.cancelScan()
                }) {
                    ScrollView {
                        SkeletonGrid(columns: 3, rows: 5)
                            .padding(Spacing.xs)
                    }
                }
            } else if viewModel.screenshots.isEmpty {
                EmptyStateView(
                    icon: "camera.viewfinder",
                    title: "No Screenshots",
                    message: "You don't have any screenshots in your library.",
                    // D-07: the empty state needs a refresh affordance — new
                    // screenshots (or imports) may have landed since the last
                    // fetch.
                    actionTitle: "Refresh"
                ) {
                    Task { await viewModel.refresh() }
                }
            } else {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("\(viewModel.screenshots.count) screenshots \u{00B7} \(viewModel.totalSize.formattedFileSize)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Review with Swipe") {
                            HapticHelper.impact(.light)
                            startSwipeReview(with: .screenshots)
                        }
                        .font(.caption.bold())
                        .frame(minHeight: 44)

                        Picker("Sort", selection: $viewModel.sortOrder) {
                            ForEach(ScreenshotSortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: Spacing.xs) {
                            ForEach(viewModel.sortedScreenshots) { screenshot in
                                screenshotCell(screenshot)
                            }
                        }
                    }
                    .pullToRefresh { await viewModel.refresh() }

                    // Bottom action bar
                    if !viewModel.selectedIds.isEmpty {
                        ActionBarView {
                            Text("\(viewModel.selectedIds.count) selected \u{00B7} \(viewModel.selectedSize.formattedFileSize)")
                                .font(.caption)
                            if viewModel.isDeleting {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .font(.headline)
                            }
                            .disabled(viewModel.isDeleting)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.reduceMotionAware(.spring(response: 0.35, dampingFraction: 0.85), reduceMotion: reduceMotion), value: viewModel.isLoading)
        .navigationTitle("Screenshots")
        // Items deleted elsewhere (Swipe Review, the Photos app) leave the
        // list when the library changes, instead of lingering as blanks.
        .task(id: libraryMonitor.generation) {
            await viewModel.pruneDeleted()
        }
        .happyPathCelebration(isPresented: $isCelebrating, statLine: "cleared \(viewModel.deletedCount) screenshots")
        .onDisappear {
            // D-01: stop an in-flight fetch when the user leaves the screen.
            viewModel.cancelScan()
        }
        .toolbar {
            // "Review with Swipe" lives in the header row only.
            if !viewModel.screenshots.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    SelectAllToolbarButton(
                        allSelected: viewModel.allVisibleSelected,
                        selectAll: { viewModel.selectAll() },
                        deselectAll: { viewModel.deselectAll() }
                    )
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
        .alert("Delete Screenshots", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.selectedIds.count) Screenshots", role: .destructive) {
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
        // Non-modal error surface. `safeAreaInset` pushes the grid down rather
        // than floating the banner over its first row.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = viewModel.errorMessage {
                ToolErrorBanner(
                    message: message,
                    title: "Screenshots",
                    onDismiss: { viewModel.errorMessage = nil }
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
            }
        }
        .alert("Delete Screenshot", isPresented: .init(
            get: { cellToDelete != nil },
            set: { if !$0 { cellToDelete = nil } }
        ), presenting: cellToDelete) { asset in
            Button("Cancel", role: .cancel) { cellToDelete = nil }
            Button("Delete", role: .destructive) {
                let id = asset.id
                cellToDelete = nil
                Task { await viewModel.delete(assetId: id) }
            }
        } message: { _ in
            Text(CleanupDeletion.recoverableNote)
        }
        .fullScreenCover(item: $previewAsset, onDismiss: {
            if pendingSwipeReview {
                pendingSwipeReview = false
                startSwipeReview(with: .screenshots)
            }
        }) { asset in
            MediaPreviewView(
                assets: viewModel.sortedScreenshots,
                startIndex: viewModel.sortedScreenshots.firstIndex { $0.id == asset.id } ?? 0,
                photoService: photoService,
                onDelete: { await viewModel.delete(assetId: $0.id) },
                accessory: AccessoryAction(title: "Review with Swipe", systemImage: "hand.draw") {
                    pendingSwipeReview = true
                }
            )
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private func startSwipeReview(with filter: SwipeFilter) {
        selectedSwipeRoute = SwipeSessionRoute(filter: filter)
    }

    private func screenshotCell(_ screenshot: AssetSummary) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    AsyncThumbnailView(assetId: screenshot.id, photoService: photoService)
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Spacing.xs))

            // Always-visible selection checkbox. Tapping it (de)selects; tapping
            // anywhere else on the cell opens the preview.
            Button {
                HapticHelper.selection()
                viewModel.toggleSelection(screenshot.id)
            } label: {
                Image(systemName: viewModel.selectedIds.contains(screenshot.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(viewModel.selectedIds.contains(screenshot.id) ? .blue : .white)
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .padding(Spacing.sm)
                    .scaleEffect(viewModel.selectedIds.contains(screenshot.id) ? 1.0 : 0.9)
                    .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: viewModel.selectedIds.contains(screenshot.id))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.selectedIds.contains(screenshot.id) ? "Deselect screenshot" : "Select screenshot")
            .accessibilityAddTraits(viewModel.selectedIds.contains(screenshot.id) ? [.isButton, .isSelected] : .isButton)
        }
        .overlay {
            if viewModel.selectedIds.contains(screenshot.id) {
                RoundedRectangle(cornerRadius: Spacing.xs)
                    .strokeBorder(Color.blue, lineWidth: 2)
            }
        }
        .onTapGesture {
            previewAsset = screenshot
        }
        .contextMenu {
            Button {
                previewAsset = screenshot
            } label: {
                Label("Preview", systemImage: "eye")
            }
            Button(role: .destructive) {
                cellToDelete = screenshot
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
