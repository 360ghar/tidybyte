import SwiftUI

struct LargeFilesView: View {
    @State private var viewModel = LargeFilesViewModel()
    @State private var showDeleteConfirm = false
    @State private var previewStart: AssetSummary?
    @State private var rowToDelete: AssetSummary?
    /// Mirrors SettingsView's control so the threshold never diverges between
    /// screens while the tool is open (LF-06).
    @AppStorage(AppPreferences.Key.largeFileThresholdMB) private var thresholdMB: Double = 10.0
    private let photoService = PhotoLibraryService()

    var body: some View {
        Group {
            if viewModel.isLoading {
                List {
                    ForEach(0..<8, id: \.self) { _ in
                        SkeletonRow()
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            } else {
                VStack(spacing: 0) {
                    // Controls
                    VStack(spacing: Spacing.sm) {
                        HStack {
                            // Binary display, consistent with each row's
                            // `formattedFileSize` (LF-05).
                            Text(LargeFilesViewModel.minSizeLabel(thresholdMB: thresholdMB))
                                .font(.caption)
                            Spacer()
                            Text("\(viewModel.filteredAssets.count) files \u{00B7} \(viewModel.totalSize.formattedFileSize)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $thresholdMB, in: 5...500, step: 5)

                        Picker("Filter", selection: $viewModel.mediaFilter) {
                            ForEach(LargeFileFilter.allCases, id: \.self) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("Sort", selection: $viewModel.sortOrder) {
                            ForEach(LargeFileSortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(Spacing.lg)
                    .readableWidth()

                    if viewModel.filteredAssets.isEmpty {
                        emptyResultsView
                    } else {
                        List {
                            ForEach(viewModel.filteredAssets) { asset in
                                fileRow(asset)
                            }
                            if viewModel.zeroSizeCount > 0 {
                                Text("\(viewModel.zeroSizeCount) items with unknown size are not listed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .listRowSeparator(.hidden)
                            }
                        }
                        .listStyle(.plain)
                        .pullToRefresh { await viewModel.refresh() }
                    }

                    if !viewModel.selectedIds.isEmpty {
                        ActionBarView {
                            if viewModel.isPreparingShare {
                                ProgressView()
                                    .padding(.trailing, Spacing.sm)
                                Text("Preparing \(viewModel.shareProgress.completed)/\(viewModel.shareProgress.total)\u{2026}")
                                    .font(.caption)
                                Spacer()
                                Button("Cancel") { viewModel.cancelShare() }
                            } else {
                                Text("\(viewModel.selectedVisibleCount) selected \u{00B7} \(viewModel.selectedSize.formattedFileSize)")
                                    .font(.caption)
                                Spacer()
                                Button { viewModel.startShare() } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.headline)
                                }
                                .accessibilityLabel("Share selected")
                                Button(role: .destructive) { showDeleteConfirm = true } label: {
                                    Label("Delete", systemImage: "trash")
                                        .font(.headline)
                                }
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isLoading)
        .navigationTitle("Large Files")
        .toolbar {
            if !viewModel.filteredAssets.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    SelectAllToolbarButton(
                        allSelected: viewModel.areAllVisibleSelected,
                        selectAll: { viewModel.selectAll() },
                        deselectAll: { viewModel.deselectAll() }
                    )
                }
            }
        }
        .alert("Delete Files", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.selectedVisibleCount) Files", role: .destructive) {
                Task { await viewModel.deleteSelected() }
            }
        } message: {
            Text("This will delete \(viewModel.selectedSize.formattedFileSize) of media. This action cannot be undone.")
        }
        .alert("Large Files Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Delete File", isPresented: .init(
            get: { rowToDelete != nil },
            set: { if !$0 { rowToDelete = nil } }
        ), presenting: rowToDelete) { asset in
            Button("Cancel", role: .cancel) { rowToDelete = nil }
            Button("Delete", role: .destructive) {
                let id = asset.id
                rowToDelete = nil
                Task { await viewModel.deleteAsset(id: id) }
            }
        } message: { asset in
            Text("This will delete \(asset.formattedFileSize). This action cannot be undone.")
        }
        .fullScreenCover(item: $previewStart) { start in
            MediaPreviewView(
                assets: viewModel.filteredAssets,
                startIndex: viewModel.filteredAssets.firstIndex { $0.id == start.id } ?? 0,
                photoService: photoService,
                onDelete: { await viewModel.deleteAsset(id: $0.id) }
            )
        }
        .sheet(item: $viewModel.sharePayload, onDismiss: { viewModel.cleanupShareExport() }) { payload in
            ShareSheet(urls: payload.urls)
        }
        .onChange(of: thresholdMB) { _, _ in
            viewModel.synchronizeSelection()
        }
        .onChange(of: viewModel.mediaFilter) { _, _ in
            viewModel.synchronizeSelection()
        }
        .onChange(of: viewModel.sortOrder) { _, _ in
            viewModel.synchronizeSelection()
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    @ViewBuilder
    private var emptyResultsView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: emptyIcon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text(emptyTitle)
                .font(.headline)
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            if viewModel.zeroSizeCount > 0 {
                Text("\(viewModel.zeroSizeCount) items with unknown size are not listed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .padding(.horizontal, Spacing.xxxl)
                    .padding(.vertical, Spacing.md)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            .scaleOnPress()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyIcon: String {
        switch viewModel.mediaFilter {
        case .all: "externaldrive"
        case .photos: "photo"
        case .videos: "video"
        }
    }

    private var emptyTitle: String {
        switch viewModel.mediaFilter {
        case .all: "No Large Files"
        case .photos: "No Large Photos"
        case .videos: "No Large Videos"
        }
    }

    private var emptyMessage: String {
        let threshold = Int(thresholdMB)
        switch viewModel.mediaFilter {
        case .all:
            return "No files larger than \(threshold) MB. Lower the threshold to see more."
        case .photos:
            return "No photos larger than \(threshold) MB. Lower the threshold or switch to All/Videos."
        case .videos:
            return "No videos larger than \(threshold) MB. Lower the threshold or switch to All/Photos."
        }
    }

    private func fileRow(_ asset: AssetSummary) -> some View {
        HStack(spacing: Spacing.md) {
            // Always-visible selection checkbox. Tapping it (de)selects the row;
            // tapping anywhere else on the row opens the preview.
            Button {
                HapticHelper.selection()
                viewModel.toggleSelection(asset.id)
            } label: {
                Image(systemName: viewModel.selectedIds.contains(asset.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(viewModel.selectedIds.contains(asset.id) ? .blue : .secondary)
                    .scaleEffect(viewModel.selectedIds.contains(asset.id) ? 1.0 : 0.9)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: viewModel.selectedIds.contains(asset.id))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.selectedIds.contains(asset.id) ? "Deselect file" : "Select file")
            .accessibilityAddTraits(viewModel.selectedIds.contains(asset.id) ? [.isButton, .isSelected] : .isButton)

            AsyncThumbnailView(assetId: asset.id, photoService: photoService)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let filename = asset.filename, !filename.isEmpty {
                    Text(filename)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                }
                HStack(spacing: Spacing.xs) {
                    Image(systemName: asset.mediaType == .video ? "video" : "photo")
                        .font(.caption)
                    if let date = asset.creationDate {
                        Text(date, style: .date)
                            .font(.subheadline)
                    }
                }

                Text(asset.resolution)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if asset.mediaType == .video {
                    Text(asset.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(asset.formattedFileSize)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)

            Button(role: .destructive) {
                rowToDelete = asset
            } label: {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundStyle(.red)
                    .padding(.leading, Spacing.xs)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete file")
        }
        .contentShape(Rectangle())
        .onTapGesture { previewStart = asset }
    }
}
