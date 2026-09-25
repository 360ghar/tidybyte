import SwiftUI

struct LargeFilesView: View {
    @State private var viewModel = LargeFilesViewModel()
    @State private var showDeleteConfirm = false
    @State private var previewStart: AssetSummary?
    @State private var rowToDelete: AssetSummary?
    @State private var isCelebrating = false
    @State private var celebrationStatLine: String?
    @State private var toast: ToastMessage?
    /// Mirrors SettingsView's control so the threshold never diverges between
    /// screens while the tool is open (LF-06).
    @AppStorage(AppPreferences.Key.largeFileThresholdMB) private var thresholdMB: Double = 10.0
    private let photoService = PhotoLibraryService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if viewModel.isLoading {
                ToolLoadingView { ToolSkeletonList(rows: 8) }
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
                                // Picks hidden by the media filter or sort order
                                // are kept, but only the visible ones are shared
                                // or deleted. A pick that falls below the size
                                // slider is cleared on the next refresh, which
                                // raises a toast instead of dropping it quietly.
                                let hidden = viewModel.selectedIds.count - viewModel.selectedVisibleCount
                                Text(hidden > 0
                                     ? "\(viewModel.selectedVisibleCount) selected \u{00B7} \(viewModel.selectedSize.formattedFileSize) (\(hidden) hidden by filter)"
                                     : "\(viewModel.selectedVisibleCount) selected \u{00B7} \(viewModel.selectedSize.formattedFileSize)")
                                    .font(.caption)
                                Spacer()
                                Button { viewModel.startShare() } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.headline)
                                }
                                .accessibilityLabel("Share selected")
                                .disabled(viewModel.selectedVisibleCount == 0)
                                Button(role: .destructive) { showDeleteConfirm = true } label: {
                                    Label("Delete", systemImage: "trash")
                                        .font(.headline)
                                }
                                .disabled(viewModel.selectedVisibleCount == 0)
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.reduceMotionAware(.spring(response: 0.35, dampingFraction: 0.85), reduceMotion: reduceMotion), value: viewModel.isLoading)
        .navigationTitle("Large Files")
        .happyPathCelebration(isPresented: $isCelebrating, statLine: celebrationStatLine)
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
                // Captured before the await — the selection clears on success.
                let count = viewModel.selectedVisibleCount
                Task {
                    await viewModel.deleteSelected()
                    // This tool fired no success feedback before; parity with
                    // the other cleanup tools (haptic every time, rating
                    // prompt only on milestones).
                    // Guard the count: the VM no-ops an empty selection
                    // without setting an error, and a no-op is not a success.
                    guard count > 0, viewModel.errorMessage == nil else { return }
                    HappyPathReporter.fire(
                        isCelebrating: $isCelebrating,
                        statLine: $celebrationStatLine,
                        line: "cleared \(count) large files"
                    )
                }
            }
        } message: {
            Text("This will delete \(viewModel.selectedSize.formattedFileSize) of media. \(CleanupDeletion.recoverableNote)")
        }
        // Non-modal error surface. `safeAreaInset` pushes the list down rather
        // than floating the banner over its first row.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = viewModel.errorMessage {
                ToolErrorBanner(
                    message: message,
                    title: "Large Files",
                    onDismiss: { viewModel.errorMessage = nil }
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
            }
        }
        .toast($toast)
        // A load/refresh that had to clear picks below the size slider says so,
        // instead of the selection just disappearing.
        .onChange(of: viewModel.droppedSelectionNotice) { _, notice in
            guard let notice else { return }
            toast = ToastMessage(text: notice.text, systemImage: "info.circle")
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
            Text("This will delete \(asset.displaySize). \(CleanupDeletion.recoverableNote)")
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
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    @ViewBuilder
    private var emptyResultsView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: emptyIcon)
                .scaledGlyph(48, weight: .light)
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
            SelectToggle(isSelected: viewModel.selectedIds.contains(asset.id), itemName: "file", overPhoto: false) {
                viewModel.toggleSelection(asset.id)
            }

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

            Text(asset.displaySize)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)

            Button(role: .destructive) {
                rowToDelete = asset
            } label: {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundStyle(.red)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete file")
        }
        .contentShape(Rectangle())
        .onTapGesture { previewStart = asset }
    }
}
