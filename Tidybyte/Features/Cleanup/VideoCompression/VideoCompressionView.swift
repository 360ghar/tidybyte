import SwiftUI
import SwiftData
import StoreKit

struct VideoCompressionView: View {
    @State private var viewModel = VideoCompressionViewModel()
    @State private var showCompressConfirm = false
    @State private var previewStart: VideoItem?
    @State private var rowToDelete: VideoItem?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    @State private var isCelebrating = false
    @State private var celebrationStatLine: String?
    private let photoService = PhotoLibraryService.shared

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.videos.isEmpty {
                EmptyStateView(
                    icon: "video.badge.waveform",
                    title: "No Videos",
                    message: "You don't have any videos in your library.",
                    iconColor: .purple
                )
            } else {
                contentView
            }
        }
        .navigationTitle("Video Compression")
        .happyPathCelebration(isPresented: $isCelebrating, statLine: celebrationStatLine)
        .toolbar {
            if !viewModel.isLoading && !viewModel.videos.isEmpty {
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
        .alert("Compress Videos", isPresented: $showCompressConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Compress \(viewModel.selectedIds.count) Videos", role: .destructive) {
                viewModel.startBatchCompression(modelContext: modelContext)
            }
        } message: {
            Text("This replaces the original videos with compressed copies. Some video metadata may not be preserved. This cannot be undone.")
        }
        // Non-modal error surface. Also covers the batch summary
        // ("Compressed 8 of 10. 2 failed."), which is a report rather than a
        // failure, so no retry is offered.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = viewModel.errorMessage {
                ToolErrorBanner(
                    message: message,
                    title: "Video Compression",
                    onDismiss: { viewModel.errorMessage = nil }
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
            }
            // Pre-compression headroom gate. A modal before; a banner now, so
            // the user keeps the selection and can deselect the largest items
            // instead of starting over after dismissing an alert.
            if viewModel.insufficientDiskSpace {
                ToolErrorBanner(
                    message: "There isn't enough free space to compress the selected videos. Free up some space and try again.",
                    title: "Not Enough Space",
                    onDismiss: { viewModel.insufficientDiskSpace = false }
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
            }
        }
        .alert("Delete Video", isPresented: .init(
            get: { rowToDelete != nil },
            set: { if !$0 { rowToDelete = nil } }
        ), presenting: rowToDelete) { video in
            Button("Cancel", role: .cancel) { rowToDelete = nil }
            Button("Delete", role: .destructive) {
                let id = video.id
                rowToDelete = nil
                Task { await viewModel.deleteVideo(id: id) }
            }
        } message: { video in
            Text("This will delete \(video.asset.displaySize). This action cannot be undone.")
        }
        .fullScreenCover(item: $previewStart) { start in
            // COMP-05: resolve the pager's assets live from the VM (via the
            // provider closure) instead of a snapshot taken at presentation, so
            // a delete inside the preview re-renders the pager against the
            // fresh list and `.onChange(of: assets)` fires.
            MediaPreviewView(
                assetsProvider: { viewModel.sortedVideos.map(\.asset) },
                startIndex: viewModel.sortedVideos.firstIndex { $0.id == start.id } ?? 0,
                photoService: photoService,
                onDelete: { await viewModel.deleteVideo(id: $0.id) }
            )
        }
        .onChange(of: viewModel.batchSummary) { _, summary in
            // Success haptic only when every attempted item succeeded and at
            // least one was compressed (COMP-09 pattern).
            guard let summary else { return }
            if summary.failed == 0, summary.completed > 0, !summary.cancelled {
                HappyPathReporter.fire(
                    isCelebrating: $isCelebrating,
                    statLine: $celebrationStatLine,
                    line: "compressed \(summary.completed) videos",
                    requestReview: requestReview
                )
            }
        }
        .onDisappear {
            // Don't orphan the mutation loop when the user leaves the screen.
            viewModel.cancelCompression()
        }
        .task {
            // D1: reconcile BEFORE loading — resolving interrupted swaps may
            // delete orphaned replacements from the library, so the list loaded
            // after it never shows just-deleted orphans.
            await CompressionJournal.reconcile(modelContext: modelContext)
            await viewModel.loadIfNeeded()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        ToolLoadingView { ToolSkeletonList() }
    }

    // MARK: - Content View

    private var contentView: some View {
        VStack(spacing: 0) {
            List {
                ForEach(Array(viewModel.sortedVideos.enumerated()), id: \.element.id) { index, video in
                    videoRow(video)
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

    // MARK: - Video Row

    private func videoRow(_ video: VideoItem) -> some View {
        HStack(spacing: Spacing.md) {
            // Always-visible selection checkbox. Tapping it (de)selects the row;
            // tapping anywhere else on the row opens the preview.
            Button {
                HapticHelper.selection()
                viewModel.toggleSelection(video.id)
            } label: {
                Image(systemName: viewModel.selectedIds.contains(video.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(viewModel.selectedIds.contains(video.id) ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.selectedIds.contains(video.id) ? "Deselect video" : "Select video")
            .accessibilityAddTraits(viewModel.selectedIds.contains(video.id) ? [.isButton, .isSelected] : .isButton)

            AsyncThumbnailView(assetId: video.id, photoService: photoService)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                .overlay(alignment: .bottomLeading) {
                    Text(video.asset.formattedDuration)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.xs))
                        .padding(Spacing.xs)
                }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let date = video.asset.creationDate {
                    Text(date, style: .date)
                        .font(.subheadline)
                }
                Menu {
                    ForEach(CompressionPreset.presets) { preset in
                        Button(preset.label) {
                            viewModel.setPreset(preset, for: video.id)
                        }
                    }
                } label: {
                    Text(video.selectedPreset.label)
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                }

                Text(video.asset.resolution)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                compressionStateLabel(video)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(video.asset.displaySize)
                    .font(.headline.monospacedDigit())

                let estimated = viewModel.estimateSize(for: video)
                if estimated < video.asset.fileSize {
                    Text("\u{2192} ~\(estimated.formattedFileSize)")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            if !viewModel.isCompressing {
                Button(role: .destructive) {
                    rowToDelete = video
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundStyle(.red)
                        .padding(.leading, Spacing.xs)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete video")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { previewStart = video }
    }

    // MARK: - Compression State Label

    @ViewBuilder
    private func compressionStateLabel(_ video: VideoItem) -> some View {
        switch video.compressionState {
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
