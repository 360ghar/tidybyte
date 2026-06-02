import SwiftUI
import SwiftData

struct ScreenshotCleanerView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ScreenshotCleanerViewModel()
    @State private var showDeleteConfirm = false
    @State private var selectedSwipeRoute: SwipeSessionRoute?
    @State private var previewAsset: AssetSummary?
    @State private var pendingSwipeReview = false
    @State private var cellToDelete: AssetSummary?

    private let photoService = PhotoLibraryService()

    private let columns = ResponsiveGrid.photo()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ScrollView {
                    SkeletonGrid(columns: 3, rows: 5)
                        .padding(Spacing.xs)
                }
            } else if viewModel.screenshots.isEmpty {
                EmptyStateView(
                    icon: "camera.viewfinder",
                    title: "No Screenshots",
                    message: "You don't have any screenshots in your library."
                )
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

                            Spacer()

                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .font(.headline)
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isLoading)
        .navigationTitle("Screenshots")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.screenshots.isEmpty {
                    HStack(spacing: Spacing.md) {
                        Button {
                            HapticHelper.impact(.light)
                            startSwipeReview(with: .screenshots)
                        } label: {
                            Image(systemName: "hand.draw")
                        }
                    }
                }
            }
            if !viewModel.screenshots.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button(viewModel.selectedIds.count == viewModel.screenshots.count ? "Deselect All" : "Select All") {
                        if viewModel.selectedIds.count == viewModel.screenshots.count {
                            viewModel.deselectAll()
                        } else {
                            viewModel.selectAll()
                        }
                    }
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
                Task { await viewModel.deleteSelected() }
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Screenshot Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
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
            Text("This action cannot be undone.")
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
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: viewModel.selectedIds.contains(screenshot.id))
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
