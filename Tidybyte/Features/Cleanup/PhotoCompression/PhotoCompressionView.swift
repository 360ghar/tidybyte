import SwiftUI
import SwiftData

struct PhotoCompressionView: View {
    @State private var viewModel = PhotoCompressionViewModel()
    @State private var showCompressConfirm = false
    @State private var previewStart: PhotoItem?
    @State private var rowToDelete: PhotoItem?
    @Environment(\.modelContext) private var modelContext
    private let photoService = PhotoLibraryService()

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.photos.isEmpty {
                EmptyStateView(
                    icon: "photo.badge.arrow.down",
                    title: "No Photos",
                    message: "You don't have any photos to compress.",
                    iconColor: .mint
                )
            } else {
                contentView
            }
        }
        .navigationTitle("Photo Compression")
        .toolbar {
            if !viewModel.isLoading && !viewModel.photos.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    SelectAllToolbarButton(
                        allSelected: viewModel.allSelected,
                        selectAll: { viewModel.selectAll() },
                        deselectAll: { viewModel.deselectAll() }
                    )
                    .disabled(viewModel.isCompressing)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: Spacing.md) {
                    NavigationLink {
                        CompressionHistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
        }
        .alert("Compress Photos", isPresented: $showCompressConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Compress \(viewModel.selectedIds.count) Photos", role: .destructive) {
                viewModel.startBatchCompression(modelContext: modelContext)
            }
        } message: {
            Text("This replaces the originals with re-encoded copies. Some photo metadata may not be preserved. This cannot be undone.")
        }
        .alert("Compression Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Not Enough Space", isPresented: $viewModel.insufficientDiskSpace) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("There isn't enough free space to compress the selected photos. Free up some space and try again.")
        }
        .alert("Delete Photo", isPresented: .init(
            get: { rowToDelete != nil },
            set: { if !$0 { rowToDelete = nil } }
        ), presenting: rowToDelete) { photo in
            Button("Cancel", role: .cancel) { rowToDelete = nil }
            Button("Delete", role: .destructive) {
                let id = photo.id
                rowToDelete = nil
                Task { await viewModel.deletePhoto(id: id) }
            }
        } message: { photo in
            Text("This will delete \(photo.asset.formattedFileSize). This action cannot be undone.")
        }
        .fullScreenCover(item: $previewStart) { start in
            // COMP-05: resolve the pager's assets live from the VM (via the
            // provider closure) instead of a snapshot taken at presentation, so
            // a delete inside the preview re-renders the pager against the
            // fresh list and `.onChange(of: assets)` fires.
            MediaPreviewView(
                assetsProvider: { viewModel.sortedPhotos.map(\.asset) },
                startIndex: viewModel.sortedPhotos.firstIndex { $0.id == start.id } ?? 0,
                photoService: photoService,
                onDelete: { await viewModel.deletePhoto(id: $0.id) }
            )
        }
        .onChange(of: viewModel.batchSummary) { _, summary in
            // Success haptic only when every attempted item succeeded and at
            // least one was compressed (COMP-09 pattern).
            guard let summary else { return }
            if summary.failed == 0, summary.completed > 0, !summary.cancelled {
                HapticHelper.notification(.success)
            }
        }
        .onDisappear {
            // Don't orphan the mutation loop when the user leaves the screen.
            viewModel.cancelCompression()
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        List {
            ForEach(0..<6, id: \.self) { _ in
                SkeletonRow()
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }

    // MARK: - Content View

    private var contentView: some View {
        VStack(spacing: 0) {
            List {
                ForEach(Array(viewModel.sortedPhotos.enumerated()), id: \.element.id) { index, photo in
                    photoRow(photo)
                        .fadeSlideIn(delay: Double(index) * 0.03)
                }
            }
            .listStyle(.plain)
            .pullToRefresh { await viewModel.refresh() }

            if !viewModel.selectedIds.isEmpty {
                bottomBar
            }
        }
    }

    // MARK: - Photo Row

    private func photoRow(_ photo: PhotoItem) -> some View {
        HStack(spacing: Spacing.md) {
            // Always-visible selection checkbox. Tapping it (de)selects the row;
            // tapping anywhere else on the row opens the preview.
            Button {
                HapticHelper.selection()
                viewModel.toggleSelection(photo.id)
            } label: {
                Image(systemName: viewModel.selectedIds.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(viewModel.selectedIds.contains(photo.id) ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.selectedIds.contains(photo.id) ? "Deselect photo" : "Select photo")
            .accessibilityAddTraits(viewModel.selectedIds.contains(photo.id) ? [.isButton, .isSelected] : .isButton)

            AsyncThumbnailView(assetId: photo.id, photoService: photoService)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let date = photo.asset.creationDate {
                    Text(date, style: .date)
                        .font(.subheadline)
                }
                Menu {
                    ForEach(PhotoCompressionPreset.presets) { preset in
                        Button(preset.label) {
                            viewModel.setPreset(preset, for: photo.id)
                        }
                    }
                } label: {
                    Text(photo.selectedPreset.label)
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                }

                Text(photo.asset.resolution)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                compressionStateLabel(photo)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(photo.asset.formattedFileSize)
                    .font(.headline.monospacedDigit())

                let estimated = viewModel.estimateSize(for: photo)
                if estimated < photo.asset.fileSize {
                    Text("\u{2192} ~\(estimated.formattedFileSize)")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            if !viewModel.isCompressing {
                Button(role: .destructive) {
                    rowToDelete = photo
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundStyle(.red)
                        .padding(.leading, Spacing.xs)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete photo")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { previewStart = photo }
    }

    // MARK: - Compression State Label

    @ViewBuilder
    private func compressionStateLabel(_ photo: PhotoItem) -> some View {
        switch photo.compressionState {
        case .waiting:
            EmptyView()
        case .exporting(let progress):
            ProgressView(value: progress)
                .tint(.blue)
                .frame(width: 80)
        case .completed(let saved):
            Text(saved > 0 ? "Saved \(saved.formattedFileSize)" : "No savings")
                .font(.caption)
                .foregroundStyle(saved > 0 ? .green : .secondary)
        case .keptOriginal(let reason):
            Text(reason)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        case .failed(let msg):
            Text(msg)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        ActionBarView {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("\(viewModel.selectedIds.count) selected")
                    .font(.caption.bold())
                Text(viewModel.selectedSize.formattedFileSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isCompressing {
                HStack(spacing: Spacing.md) {
                    ProgressView()
                    Text("Compressing...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        HapticHelper.impact(.light)
                        viewModel.cancelCompression()
                    } label: {
                        Text("Cancel")
                            .font(.subheadline.bold())
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel compression")
                }
            } else {
                Button {
                    HapticHelper.impact(.light)
                    showCompressConfirm = true
                } label: {
                    Text("Compress")
                        .font(.headline)
                        .padding(.horizontal, Spacing.xxl)
                        .padding(.vertical, Spacing.sm)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                }
                .scaleOnPress()
            }
        }
    }
}
