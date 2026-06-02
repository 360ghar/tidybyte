import SwiftUI
import SwiftData

struct VideoCompressionView: View {
    @State private var viewModel = VideoCompressionViewModel()
    @State private var showCompressConfirm = false
    @State private var previewStart: VideoItem?
    @State private var rowToDelete: VideoItem?
    @Environment(\.modelContext) private var modelContext
    private let photoService = PhotoLibraryService()

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
        .toolbar {
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
                Task {
                    await viewModel.compressSelected(modelContext: modelContext)
                    HapticHelper.notification(.success)
                }
            }
        } message: {
            Text("This will replace the original videos with compressed versions. This action cannot be undone.")
        }
        .alert("Compression Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
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
            Text("This will delete \(video.asset.formattedFileSize). This action cannot be undone.")
        }
        .fullScreenCover(item: $previewStart) { start in
            MediaPreviewView(
                assets: viewModel.sortedVideos.map(\.asset),
                startIndex: viewModel.sortedVideos.firstIndex { $0.id == start.id } ?? 0,
                photoService: photoService,
                onDelete: { await viewModel.deleteVideo(id: $0.id) }
            )
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
                Text(video.asset.formattedFileSize)
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
        case .saving:
            Text("Saving...")
                .font(.caption)
                .foregroundStyle(.blue)
        case .completed(let saved):
            Text("Saved \(saved.formattedFileSize)")
                .font(.caption)
                .foregroundStyle(.green)
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
                ProgressView()
                    .padding(.trailing, Spacing.sm)
                Text("Compressing...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
