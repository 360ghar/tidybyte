import SwiftUI
import Photos
import SwiftData

/// Full-screen, paged preview of a Live Photo list. Lets the user open a
/// single Live Photo to play its motion, then choose one of three actions:
///
/// - **Convert to Still** — the existing safe flow: a still asset is created
///   from the Live Photo's still component, then the original Live Photo is
///   deleted.
/// - **Delete Live Photo** — deletes both the still and the motion
///   component. Use when the user doesn't want to keep a still at all.
/// - **Keep** — close the preview without changes.
///
/// Swipe horizontally (TabView page style) to review each Live Photo in
/// sequence. The preview always reflects the latest list state from
/// `viewModel.items` and auto-advances after a successful Convert/Delete.
struct LivePhotoPreviewView: View {
    @Bindable var viewModel: LivePhotosConverterViewModel
    let startItemId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var currentIndex: Int
    @State private var showDeleteConfirm = false
    @State private var showConvertExplainer = false
    @AppStorage(LivePhotoConvertExplainer.storageKey) private var hasSeenExplainer = false

    private let photoService = PhotoLibraryService.shared

    init(viewModel: LivePhotosConverterViewModel, startItemId: String) {
        self.viewModel = viewModel
        self.startItemId = startItemId
        let startIndex = viewModel.indexOfItem(id: startItemId) ?? 0
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.items.isEmpty {
                emptyState
            } else {
                contentView
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .task(id: viewModel.items.map(\.id).joined(separator: "|")) {
            // COMP-13: one batched pass over the user's albums (memoized on the
            // VM) instead of one fetch per item.
            await viewModel.refreshAlbumNames(for: Set(viewModel.items.map(\.id)))
        }
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)

            pagedViewer

            Spacer(minLength: 0)

            metadataAndActions
        }
        .alert("Delete Live Photo?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                HapticHelper.notification(.warning)
                Task { await performDelete() }
            }
        } message: {
            Text("This removes both the still image and the motion. \(CleanupDeletion.recoverableNote)")
        }
        .alert("Convert Live Photo", isPresented: $showConvertExplainer) {
            Button("Cancel", role: .cancel) { }
            Button("Convert") {
                hasSeenExplainer = true
                Task { await performConvert() }
            }
        } message: {
            Text(LivePhotoConvertExplainer.message)
        }
        // The list's alert cannot present over this full-screen cover.
        .originalsKeptAlert(
            isPresented: !viewModel.keptOriginals.isEmpty,
            onTryAgain: { viewModel.retryRemovingOriginals() },
            onRemoveCopies: { viewModel.removeCopies() }
        )
    }

    private var topBar: some View {
        HStack {
            Button {
                HapticHelper.impact(.light)
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(Spacing.sm)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("Close preview")

            Spacer()

            if !viewModel.items.isEmpty {
                Text("\(currentIndex + 1) of \(viewModel.items.count)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(.white.opacity(0.12), in: Capsule())
            }
        }
    }

    private var pagedViewer: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                ZStack {
                    if shouldShowPlayer(for: item) {
                        LivePhotoPlayerView(
                            assetId: item.id,
                            photoService: photoService,
                            targetSize: CGSize(width: 1200, height: 1200),
                            // D6 (COMP-14 port): only the visible page keeps its
                            // PHLivePhoto loaded — adjacent TabView pages used to
                            // pin full live-photo buffers.
                            isActive: index == currentIndex
                        )
                    }
                    conversionStateOverlay(for: item)
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(edges: .horizontal)
    }

    private func shouldShowPlayer(for item: LivePhotoItem) -> Bool {
        switch item.conversionState {
        case .idle, .converting, .copySaved, .failed:
            return true
        case .completed:
            return false
        }
    }

    @ViewBuilder
    private func conversionStateOverlay(for item: LivePhotoItem) -> some View {
        switch item.conversionState {
        case .idle, .converting, .copySaved:
            EmptyView()
        case .completed:
            VStack(spacing: Spacing.md) {
                Image(systemName: "checkmark.seal.fill")
                    .scaledGlyph(64)
                    .foregroundStyle(.green)
                Text("Converted to Still")
                    .font(.headline)
                    .foregroundStyle(.white)
                if item.savedBytes > 0 {
                    Text("Saved \(item.savedBytes.formattedFileSize)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(Spacing.xl)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: CornerRadius.large))
        case .failed(let message):
            VStack(spacing: Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .scaledGlyph(56)
                    .foregroundStyle(.red)
                Text("Conversion Failed")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 320)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: CornerRadius.large))
        }
    }

    private var metadataAndActions: some View {
        VStack(spacing: Spacing.md) {
            if let item = currentItem {
                metadataCard(for: item)
            }
            actionBar
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
    }

    private var emptyState: some View {
        PreviewEmptyState(title: "No more Live Photos")
    }

    @ViewBuilder
    private func metadataCard(for item: LivePhotoItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let date = item.asset.creationDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            HStack(spacing: Spacing.md) {
                Label(item.asset.resolution, systemImage: "rectangle.grid.1x2")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Label(item.asset.displaySize, systemImage: "internaldrive")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                if let names = viewModel.albumNamesByAsset[item.id], !names.isEmpty {
                    Label(names.joined(separator: ", "), systemImage: "rectangle.stack")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: CornerRadius.large))
    }

    private var actionBar: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                HapticHelper.impact(.light)
                dismiss()
            } label: {
                Text("Keep")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: CornerRadius.medium))
                    .foregroundStyle(.white)
            }
            .scaleOnPress()
            .accessibilityLabel("Keep Live Photo and close")

            Button(role: .destructive) {
                HapticHelper.impact(.medium)
                showDeleteConfirm = true
            } label: {
                Text("Delete")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: CornerRadius.medium))
                    .foregroundStyle(.white)
            }
            .scaleOnPress()
            .accessibilityLabel("Delete Live Photo")
            // COMP-18 parity with Convert: no outright delete while Convert All
            // is running (the batch may own this item).
            .disabled(currentItem == nil || viewModel.convertingAll || viewModel.isBusy)

            Button {
                HapticHelper.impact(.medium)
                if hasSeenExplainer {
                    Task { await performConvert() }
                } else {
                    showConvertExplainer = true
                }
            } label: {
                Group {
                    if isCurrentConverting {
                        ProgressView()
                            .tint(.white)
                    } else if isCurrentConverted {
                        Image(systemName: "checkmark")
                    } else {
                        Text("Convert")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(isCurrentConverted ? Color.gray.opacity(0.6) : Color.green, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
                .foregroundStyle(.white)
            }
            .scaleOnPress()
            // COMP-18: no single-item Convert while Convert All is running.
            .disabled(currentItem == nil || isCurrentConverting || isCurrentConverted || viewModel.convertingAll || viewModel.isBusy)
            .accessibilityLabel("Convert Live Photo to Still")
        }
    }

    // MARK: - State derived from current index

    private var currentItem: LivePhotoItem? {
        guard currentIndex >= 0, currentIndex < viewModel.items.count else { return nil }
        return viewModel.items[currentIndex]
    }

    private var isCurrentConverting: Bool {
        guard let item = currentItem else { return false }
        switch item.conversionState {
        case .converting, .copySaved: return true
        default: break
        }
        return false
    }

    private var isCurrentConverted: Bool {
        guard let item = currentItem else { return false }
        if case .completed = item.conversionState { return true }
        return false
    }

    // MARK: - Actions

    private func performConvert() async {
        guard let item = currentItem else { return }
        await viewModel.convertSingle(itemId: item.id, modelContext: modelContext)
        // The local `item` is a captured struct copy; read the current state
        // from the view model's array to know if conversion succeeded.
        if case .completed = viewModel.items.first(where: { $0.id == item.id })?.conversionState {
            HapticHelper.notification(.success)
        }
        // After convert, the item is still in the list (marked .completed) so we
        // can stay on it. User can swipe or close.
    }

    private func performDelete() async {
        guard let item = currentItem else { return }
        let deletedIndex = currentIndex
        await viewModel.deleteLivePhoto(itemId: item.id)
        // Only confirm success if the item was actually removed.
        if !viewModel.items.contains(where: { $0.id == item.id }) {
            HapticHelper.notification(.success)
        }
        // If the list still has items, keep the cursor at the same index (which
        // is now the next item). Otherwise let the empty state show.
        if !viewModel.items.isEmpty {
            let newIndex = min(deletedIndex, viewModel.items.count - 1)
            if newIndex != currentIndex {
                currentIndex = max(0, newIndex)
            }
        }
    }
}
