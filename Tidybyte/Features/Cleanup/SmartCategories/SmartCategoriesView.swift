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
    @State private var showDeleteConfirm = false
    @State private var selectedSwipeRoute: SwipeSessionRoute?
    @State private var previewPhoto: CategorizedPhoto?
    @State private var pendingSwipeReview = false
    @State private var cellToDelete: CategorizedPhoto?

    private let photoService = PhotoLibraryService()

    private let columns = ResponsiveGrid.photo()

    var body: some View {
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
            default:
                // `.error` is unreachable for this tool (de-slop) and stays in
                // the shared `ScanState` for the Duplicates/Similar tools — keep
                // the switch exhaustive with a no-op.
                EmptyView()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.scanState)
        .navigationTitle("Smart Categories")
        .onDisappear {
            // D-01: a scan left running after the user leaves the screen would
            // keep consuming CPU (and PhotoKit calls) in the background.
            viewModel.cancelScan()
        }
        .toolbar {
            if viewModel.scanState == .completed && !viewModel.filteredPhotos.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    SelectAllToolbarButton(
                        allSelected: viewModel.allVisibleSelected,
                        selectAll: { viewModel.selectAll() },
                        deselectAll: { viewModel.deselectAll() }
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: Spacing.md) {
                        Button {
                            HapticHelper.impact(.light)
                            let ids = Set(viewModel.filteredPhotos.map(\.id))
                            startSwipeReview(with: .customAssetIds(ids))
                        } label: {
                            Image(systemName: "hand.draw")
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
        .alert("Delete Photos", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.selectedIds.count) Photos", role: .destructive) {
                Task { await viewModel.deleteSelected() }
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Smart Categories Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
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
            Text("This action cannot be undone.")
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
        .onChange(of: viewModel.activeCategory) { _, _ in
            viewModel.synchronizeSelectionWithActiveCategory()
        }
    }

    private func startSwipeReview(with filter: SwipeFilter) {
        selectedSwipeRoute = SwipeSessionRoute(filter: filter)
    }

    // MARK: - Idle View

    private var idleView: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.pink.opacity(0.15), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(Color.pink.opacity(0.8))
                    .subtleShadow()
            }
            .fadeSlideIn()

            VStack(spacing: Spacing.sm) {
                Text("Organize by Content")
                    .font(.title2.bold())
                Text("Group photos into memes, documents, food, pets, nature, selfies and media saved from other apps.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxxl)
            }
            .fadeSlideIn(delay: 0.05)

            Button {
                HapticHelper.impact(.light)
                viewModel.startScan()
            } label: {
                Text("Start Analysis")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(Spacing.lg)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            .scaleOnPress()
            .padding(.horizontal, Spacing.xxxl + Spacing.sm)
            .fadeSlideIn(delay: 0.1)

            Spacer()
        }
    }

    // MARK: - Scanning View

    private func scanningView(progress: Float) -> some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            ProgressView(value: progress) {
                Text("Sorting photos...")
                    .font(.headline)
            } currentValueLabel: {
                Text("\(Int(progress * 100))% \u{00B7} \(viewModel.categorizedPhotos.count) sorted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Spacing.xxxl + Spacing.sm)

            // D-01: explicit cancel so users aren't trapped in a long scan.
            Button {
                HapticHelper.impact(.light)
                viewModel.cancelScan()
            } label: {
                Text("Cancel")
                    .font(.headline)
                    .padding(.horizontal, Spacing.xxxl)
                    .padding(.vertical, Spacing.md)
                    .background(Color.secondary.opacity(0.85))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            .scaleOnPress()
            .padding(.horizontal, Spacing.xxxl + Spacing.sm)
            Spacer()
        }
        .fadeSlideIn()
    }

    // MARK: - Results View

    private var resultsView: some View {
        VStack(spacing: 0) {
            if viewModel.categorizedPhotos.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "sparkles",
                    title: "Nothing to Sort",
                    message: "We couldn't sort any photos into categories.",
                    iconColor: .pink
                )
                Spacer()
            } else {
                categoryChips

                if viewModel.filteredPhotos.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "checkmark.circle",
                        title: "All Clear",
                        message: "No photos in this category.",
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
                    .pullToRefresh { viewModel.startScan() }

                    if !viewModel.selectedIds.isEmpty {
                        ActionBarView {
                            Text("\(viewModel.selectedIds.count) selected \u{00B7} \(viewModel.selectedSize.formattedFileSize)")
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
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(viewModel.nonEmptyCategories, id: \.self) { category in
                    let isActive = viewModel.activeCategory == category
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
            Button {
                HapticHelper.selection()
                viewModel.toggleSelection(photo.id)
            } label: {
                Image(systemName: viewModel.selectedIds.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(viewModel.selectedIds.contains(photo.id) ? .blue : .white)
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .padding(Spacing.sm)
                    .scaleEffect(viewModel.selectedIds.contains(photo.id) ? 1.0 : 0.9)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: viewModel.selectedIds.contains(photo.id))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.selectedIds.contains(photo.id) ? "Deselect photo" : "Select photo")
            .accessibilityAddTraits(viewModel.selectedIds.contains(photo.id) ? [.isButton, .isSelected] : .isButton)
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
