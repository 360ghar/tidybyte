import AVKit
import SwiftUI

/// An optional extra action shown in `MediaPreviewView`'s bottom bar (e.g.
/// "Review with Swipe"). The handler runs and then the preview dismisses, so
/// the presenting screen can react in `fullScreenCover`'s `onDismiss` to
/// navigate without fighting the cover's own dismissal animation.
struct AccessoryAction {
    let title: String
    let systemImage: String
    let handler: @MainActor () -> Void
}

/// Full-screen, horizontally-paged media viewer shared across the cleanup
/// screens. Shows photos (pinch- and double-tap-to-zoom), plays videos, and
/// plays Live Photos, with a top "i of N" bar and a bottom metadata card +
/// Delete action. Intentionally **ViewModel-agnostic**: it takes a plain
/// `[AssetSummary]` (or a closure that re-reads the caller's view model), a
/// start index, the `PhotoLibraryService`, and an optional `onDelete`
/// callback — so any screen can adopt it.
///
/// Mirrors `LivePhotoPreviewView`'s layout and post-delete index clamping, but
/// works for arbitrary media types. It reads the paged list **live**: either
/// the caller's `assets` array (recomputed by the caller each render) or an
/// `assetsProvider` closure that re-reads the presenting screen's view model.
/// When the caller's `onDelete` mutates the underlying source the preview
/// re-renders against the fresh list instead of a stale snapshot, and
/// `.onChange(of: assets)` fires because the list is re-evaluated per render
/// (COMP-05). Only the page cursor (`currentIndex`) is local state, re-clamped
/// via `.onChange(of: assets)` and after each delete.
struct MediaPreviewView: View {
    let photoService: PhotoLibraryService
    /// D5: returns whether the item actually left the caller's list, so the
    /// preview only celebrates real deletions.
    var onDelete: (@MainActor (AssetSummary) async -> Bool)?
    var accessory: AccessoryAction?

    @Environment(\.dismiss) private var dismiss
    private let staticAssets: [AssetSummary]?
    private let assetsProvider: (() -> [AssetSummary])?
    @State private var currentIndex: Int
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    /// The live paged list: the provider closure when given (re-read every
    /// render so deletes elsewhere re-render the pager), else the static array.
    private var assets: [AssetSummary] {
        assetsProvider?() ?? staticAssets ?? []
    }

    init(
        assets: [AssetSummary],
        startIndex: Int,
        photoService: PhotoLibraryService,
        onDelete: (@MainActor (AssetSummary) async -> Bool)? = nil,
        accessory: AccessoryAction? = nil
    ) {
        self.photoService = photoService
        self.onDelete = onDelete
        self.accessory = accessory
        self.staticAssets = assets
        self.assetsProvider = nil
        let clamped = max(0, min(startIndex, max(0, assets.count - 1)))
        _currentIndex = State(initialValue: clamped)
    }

    init(
        assetsProvider: @escaping () -> [AssetSummary],
        startIndex: Int,
        photoService: PhotoLibraryService,
        onDelete: (@MainActor (AssetSummary) async -> Bool)? = nil,
        accessory: AccessoryAction? = nil
    ) {
        self.photoService = photoService
        self.onDelete = onDelete
        self.accessory = accessory
        self.staticAssets = nil
        self.assetsProvider = assetsProvider
        let initial = assetsProvider()
        let clamped = max(0, min(startIndex, max(0, initial.count - 1)))
        _currentIndex = State(initialValue: clamped)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if assets.isEmpty {
                emptyState
            } else {
                contentView
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
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
        .alert("Delete Item?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                HapticHelper.notification(.warning)
                Task { await performDelete() }
            }
        } message: {
            Text("This permanently deletes this item from your photo library. This action cannot be undone.")
        }
        .onChange(of: assets) { _, newAssets in
            if newAssets.isEmpty {
                dismiss()
            } else if currentIndex >= newAssets.count {
                currentIndex = newAssets.count - 1
            }
        }
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

            Text("\(currentIndex + 1) of \(assets.count)")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(.white.opacity(0.12), in: Capsule())
        }
    }

    private var pagedViewer: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                pageContent(for: asset, index: index)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(edges: .horizontal)
    }

    @ViewBuilder
    private func pageContent(for asset: AssetSummary, index: Int) -> some View {
        if asset.mediaType == .video {
            VideoPlayerPageView(
                assetId: asset.id,
                photoService: photoService,
                isActive: index == currentIndex
            )
        } else if asset.isLivePhoto {
            // COMP-14: pass page activity so the player tears down (nils its
            // live photo) as soon as the page stops being the visible one —
            // `dismantleUIView` alone never fires for off-screen pager pages.
            LivePhotoPlayerView(
                assetId: asset.id,
                photoService: photoService,
                targetSize: CGSize(width: 1200, height: 1200),
                isActive: index == currentIndex
            )
        } else {
            ZoomableImageView(assetId: asset.id, photoService: photoService)
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

    @ViewBuilder
    private func metadataCard(for asset: AssetSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let filename = asset.filename, !filename.isEmpty {
                Text(filename)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } else if let date = asset.creationDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            HStack(spacing: Spacing.md) {
                Label(asset.resolution, systemImage: "rectangle.grid.1x2")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Label(asset.displaySize, systemImage: "internaldrive")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                if asset.mediaType == .video, !asset.formattedDuration.isEmpty {
                    Label(asset.formattedDuration, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
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
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: CornerRadius.medium))
                    .foregroundStyle(.white)
            }
            .scaleOnPress()
            .accessibilityLabel("Close preview")

            if let accessory {
                Button {
                    HapticHelper.impact(.light)
                    accessory.handler()
                    dismiss()
                } label: {
                    Label(accessory.title, systemImage: accessory.systemImage)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: CornerRadius.medium))
                        .foregroundStyle(.white)
                }
                .scaleOnPress()
            }

            if onDelete != nil {
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
                .disabled(currentItem == nil || isDeleting)
                .accessibilityLabel("Delete item")
            }
        }
    }

    private var emptyState: some View {
        PreviewEmptyState(title: "No more items")
    }

    // MARK: - State

    private var currentItem: AssetSummary? {
        guard currentIndex >= 0, currentIndex < assets.count else { return nil }
        return assets[currentIndex]
    }

    // MARK: - Actions

    private func performDelete() async {
        guard let item = currentItem, let onDelete, !isDeleting else { return }
        isDeleting = true
        let deletedIndex = currentIndex
        // D5: `onDelete` reports whether the item actually left the caller's
        // list — VMs catch their own errors, so without this the success
        // haptic fired even on a failed delete (and the pager advanced past
        // an item that still exists).
        let deleted = await onDelete(item)
        if deleted {
            HapticHelper.notification(.success)
        }
        isDeleting = false
        guard deleted else { return }
        // `assets` is the caller's recomputed list (item now removed). Clamp the
        // cursor; the `.onChange(of: assets)` re-clamps/dismisses once the fresh
        // array arrives, covering the main-actor render timing either way.
        if assets.isEmpty {
            dismiss()
        } else {
            currentIndex = max(0, min(deletedIndex, assets.count - 1))
        }
    }
}

// MARK: - Zoomable photo page

/// A pinch- and double-tap-zoomable full-size photo, backed by `UIScrollView`
/// so zoom/pan coexists with the enclosing `TabView` page gesture (the scroll
/// view consumes the pan only while zoomed in; at minimum zoom the page swipe
/// takes over). Loads a high-resolution image directly via the service —
/// deliberately **not** through `ImageCache.shared`, whose entries are keyed
/// for 200px thumbnails.
struct ZoomableImageView: UIViewRepresentable {
    let assetId: String
    let photoService: PhotoLibraryService
    var targetSize: CGSize = CGSize(width: 2048, height: 2048)

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> CenteringScrollView {
        let scrollView = CenteringScrollView()
        scrollView.configure()
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ scrollView: CenteringScrollView, context: Context) {
        guard context.coordinator.loadedAssetId != assetId else { return }
        context.coordinator.loadedAssetId = assetId
        scrollView.setImage(nil)

        let coordinator = context.coordinator
        let service = photoService
        let size = targetSize
        let id = assetId
        coordinator.loadTask?.cancel()
        coordinator.loadTask = Task { @MainActor in
            let image = await service.loadImage(for: id, targetSize: size, contentMode: .aspectFit)
            guard !Task.isCancelled, coordinator.loadedAssetId == id else { return }
            scrollView.setImage(image)
            if image == nil {
                // SHARED-06: a failed load clears the "loaded" marker so the
                // next render retries instead of showing a blank page forever.
                coordinator.loadedAssetId = nil
            }
        }
    }

    static func dismantleUIView(_ uiView: CenteringScrollView, coordinator: Coordinator) {
        coordinator.loadTask?.cancel()
        uiView.setImage(nil)
    }

    @MainActor
    final class Coordinator {
        weak var scrollView: CenteringScrollView?
        var loadedAssetId: String?
        var loadTask: Task<Void, Never>?
    }
}

/// `UIScrollView` subclass that displays one image at its natural aspect ratio,
/// fully visible and centered with black letterbox/pillarbox bars, and supports
/// pinch / double-tap zoom. Acts as its own delegate.
///
/// The image view is sized to the image's pixel dimensions (not the scroll
/// bounds), and `minimumZoomScale` is the scale that makes the whole image fit —
/// so at rest the complete photo is shown, and zooming/panning operate on the
/// image itself rather than on a bounds-sized frame padded with empty space
/// (the previous approach, which made zoom focal points and panning misbehave).
final class CenteringScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    /// Set when a new image is installed; consumed once bounds are known so the
    /// initial fit happens even if the view isn't laid out yet (off-screen page).
    private var needsInitialFit = false

    func configure() {
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 1
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        backgroundColor = .black
        contentInsetAdjustmentBehavior = .never
        bouncesZoom = true
        decelerationRate = .fast

        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    /// Installs a freshly-loaded image (or clears it). Sizes the content to the
    /// image's natural dimensions and schedules a fit-to-bounds reset.
    func setImage(_ image: UIImage?) {
        imageView.image = image
        guard let image, image.size.width > 0, image.size.height > 0 else {
            contentSize = .zero
            needsInitialFit = false
            return
        }
        // Reset any prior zoom from a recycled view, then size to the image.
        minimumZoomScale = 1
        maximumZoomScale = 1
        zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size
        needsInitialFit = true
        setNeedsLayout()
        fitIfNeeded()
    }

    /// The zoom scale at which the whole image fits inside the current bounds.
    private var fitScale: CGFloat {
        guard let image = imageView.image,
              image.size.width > 0, image.size.height > 0,
              bounds.width > 0, bounds.height > 0 else { return 1 }
        return min(bounds.width / image.size.width, bounds.height / image.size.height)
    }

    private func fitIfNeeded() {
        guard needsInitialFit, imageView.image != nil,
              bounds.width > 0, bounds.height > 0 else { return }
        let scale = fitScale
        minimumZoomScale = scale
        maximumZoomScale = scale * 4
        zoomScale = scale
        needsInitialFit = false
        centerImage()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if needsInitialFit {
            fitIfNeeded()
        } else if imageView.image != nil, abs(zoomScale - minimumZoomScale) < 0.0001 {
            // Already fitted and the user isn't zoomed in: keep it fitted across
            // bounds changes (e.g. rotation) without fighting an active zoom.
            let scale = fitScale
            if abs(minimumZoomScale - scale) > 0.0001 {
                minimumZoomScale = scale
                maximumZoomScale = scale * 4
                zoomScale = scale
            }
        }
        centerImage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

    /// Centers the (possibly smaller-than-bounds) content with symmetric insets —
    /// this is what produces the black bars when the image doesn't fill the frame.
    private func centerImage() {
        let offsetX = max((bounds.width - contentSize.width) * 0.5, 0)
        let offsetY = max((bounds.height - contentSize.height) * 0.5, 0)
        contentInset = UIEdgeInsets(top: offsetY, left: offsetX, bottom: offsetY, right: offsetX)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.0001 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let target = min(maximumZoomScale, minimumZoomScale * 3)
            let point = gesture.location(in: imageView)
            let width = bounds.width / target
            let height = bounds.height / target
            zoom(to: CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height), animated: true)
        }
    }
}

// MARK: - Video page

/// Plays a video asset with AVKit's standard transport controls. Loads the
/// `AVPlayerItem` lazily via the service, auto-plays only while it is the
/// active page, pauses when scrolled off, and tears the player down on
/// disappear so neighbouring pages in the pager don't pin decode buffers.
struct VideoPlayerPageView: View {
    let assetId: String
    let photoService: PhotoLibraryService
    let isActive: Bool

    @State private var player: AVPlayer?
    @State private var loadFailed = false
    /// Bumped when a torn-down page becomes active again. `assetId` alone is a
    /// stable task id, so D6's teardown (`player = nil`) would otherwise never
    /// be followed by a reload: the page would render its spinner forever.
    @State private var reloadToken = 0

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
            } else if loadFailed {
                unavailable
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task(id: "\(assetId)#\(reloadToken)") {
            loadFailed = false
            let box = await photoService.loadPlayerItem(for: assetId)
            guard !Task.isCancelled else { return }
            if let box {
                let newPlayer = AVPlayer(playerItem: box.value)
                player = newPlayer
                if isActive { newPlayer.play() }
            } else {
                loadFailed = true
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                if let player {
                    player.play()
                } else {
                    // D6 tore the player down while this page was off-screen —
                    // reload it (see reloadToken).
                    loadFailed = false
                    reloadToken += 1
                }
            } else {
                player?.pause()
                // D6: an inactive page in a TabView pager never gets
                // `onDisappear` — unload here so swiping through a video list
                // doesn't accumulate paused AVPlayerItems holding decoded
                // resources. Reloading on reactivation is cheap.
                player?.replaceCurrentItem(with: nil)
                player = nil
            }
        }
        .onDisappear {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
            loadFailed = false
        }
    }

    private var unavailable: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "video.slash")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.6))
            Text("Video unavailable")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
