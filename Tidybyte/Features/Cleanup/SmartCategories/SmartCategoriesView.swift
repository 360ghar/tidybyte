import SwiftUI
import SwiftData

// MARK: - Category UI

extension PhotoCategory {
    var title: String {
        switch self {
        case .memes: "Memes / Social"
        case .documents: "Documents"
        case .food: "Food"
        case .pets: "Pets"
        case .nature: "Nature"
        case .selfies: "Selfies"
        case .savedFromApps: "Saved from Apps"
        case .other: "Other"
        }
    }

    var icon: String {
        switch self {
        case .memes: "text.bubble"
        case .documents: "doc.text"
        case .food: "fork.knife"
        case .pets: "pawprint"
        case .nature: "leaf"
        case .selfies: "person.crop.square"
        case .savedFromApps: "square.and.arrow.down"
        case .other: "square.grid.2x2"
        }
    }

    var tint: Color {
        switch self {
        case .memes: .pink
        case .documents: .blue
        case .food: .orange
        case .pets: .brown
        case .nature: .green
        case .selfies: .purple
        case .savedFromApps: .teal
        case .other: .gray
        }
    }
}

struct SmartCategoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SmartCategoriesViewModel()
    @Environment(LibraryChangeMonitor.self) private var libraryMonitor
    @State private var showDeleteConfirm = false
    @State private var isCelebrating = false
    @State private var selectedSwipeRoute: SwipeSessionRoute?
    @State private var previewPhoto: CategorizedPhoto?
    @State private var pendingSwipeReview = false
    @State private var cellToDelete: CategorizedPhoto?

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
                    title: "Smart Categories",
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
        .navigationTitle("Smart Categories")
        // Items deleted elsewhere (Swipe Review, the Photos app) leave the
        // list when the library changes, instead of lingering as blanks.
        .task(id: libraryMonitor.generation) {
            await viewModel.pruneDeleted()
        }
        .happyPathCelebration(isPresented: $isCelebrating, statLine: "cleared \(viewModel.deletedCount) photos")
        .onDisappear {
            // D-01: a scan left running after the user leaves the screen would
            // keep consuming CPU (and PhotoKit calls) in the background.
            viewModel.cancelScan()
            viewModel.cancelSearch()
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
                            viewModel.cancelSearch()
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
            icon: "sparkles.rectangle.stack",
            tint: .pink,
            title: "Organize by Content",
            message: "Group photos into memes, documents, food, pets, nature, selfies and media saved from other apps.",
            primaryTitle: "Start Analysis",
            primaryHint: "Scans your library and sorts photos by what's in them",
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
            icon: "sparkles.rectangle.stack",
            tint: .pink,
            title: "Sorting photos...",
            progress: progress,
            // C9: results only land at scan end, so count what's actually been
            // processed — the photo total set right after the fetch.
            detail: "\(viewModel.analyzedPhotoCount) photos",
            onCancel: {
                HapticHelper.impact(.light)
                viewModel.cancelScan()
                viewModel.cancelSearch()
            }
        )
        .fadeSlideIn()
    }

    // MARK: - Results View

    private var resultsView: some View {
        VStack(spacing: 0) {
            if viewModel.categorizedPhotos.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "square.grid.2x2",
                    title: "Nothing to Sort",
                    message: "We couldn't sort any photos into categories.",
                    iconColor: .pink,
                    actionTitle: "Scan Again"
                ) {
                    viewModel.startScan()
                }
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    TextField("Search scanned photos", text: $viewModel.searchText)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit { viewModel.submitSearch() }
                    HStack {
                        Button("Search") { viewModel.submitSearch() }
                            .disabled(!viewModel.isSearchActive || viewModel.isSearching)
                        if viewModel.isSearchActive {
                            Button("Clear") { viewModel.searchText = "" }
                        }
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                if viewModel.isSearching { ProgressView("Searching on device") }
                if let message = viewModel.searchMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary).padding(.horizontal, Spacing.lg)
                }
                if viewModel.skippedAnalysisCount > 0 {
                    Text("\(viewModel.skippedAnalysisCount) photos could not be indexed from a local image.")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, Spacing.lg)
                }
                if !viewModel.isSearchActive { categoryChips }

                if viewModel.filteredPhotos.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "checkmark.circle",
                        title: viewModel.isSearchActive ? "No matching photos" : "All Clear",
                        message: viewModel.isSearchActive ? "Submit a content search or try different words." : "No photos in this category.",
                        iconColor: .green
                    )
                    Spacer()
                } else {
                    HStack {
                        Text("\(viewModel.filteredPhotos.count) photos \u{00B7} \(viewModel.activeCategorySize.formattedFileSize)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.sm)

                    // D-06: the saved-from-apps bucket is filename-heuristic;
                    // when it dominates the library, say so.
                    if let explanation = viewModel.categoryExplanation {
                        Text(explanation)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.bottom, Spacing.sm)
                    }

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: Spacing.xs) {
                            ForEach(viewModel.filteredPhotos) { photo in
                                photoCell(photo)
                            }
                        }
                    }
                }

                // Outside the list branch: picks in other categories stay
                // reachable even when this one is empty.
                    if !viewModel.selectedIds.isEmpty {
                        ActionBarView {
                            Text(viewModel.selectedInOtherCategories > 0 ? "\(viewModel.selectedIds.count) selected (\(viewModel.selectedInOtherCategories) not shown) \u{00B7} \(viewModel.selectedSize.formattedFileSize)" : "\(viewModel.selectedIds.count) selected \u{00B7} \(viewModel.selectedSize.formattedFileSize)")
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
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(viewModel.nonEmptyCategories, id: \.self) { category in
                    let isActive = viewModel.activeCategory == category
                    Button {
                        withAnimation(.reduceMotionAware(.spring(response: 0.3, dampingFraction: 0.8), reduceMotion: reduceMotion)) {
                            viewModel.activeCategory = category
                        }
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: category.icon)
                                .font(.caption)
                            Text("\(category.title) (\(viewModel.count(for: category)))")
                                .font(.subheadline.weight(isActive ? .semibold : .regular))
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(isActive ? category.tint : Color.secondary.opacity(0.15))
                        .foregroundStyle(isActive ? .white : .primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
        }
    }

    // MARK: - Photo Cell

    private func photoCell(_ photo: CategorizedPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    AsyncThumbnailView(assetId: photo.id, photoService: photoService)
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Spacing.xs))

            // Always-visible selection checkbox. Tapping it (de)selects; tapping
            // anywhere else on the cell opens the preview.
            SelectToggle(isSelected: viewModel.selectedIds.contains(photo.id), itemName: "photo") {
                viewModel.toggleSelection(photo.id)
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
}
