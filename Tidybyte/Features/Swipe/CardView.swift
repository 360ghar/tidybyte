import SwiftUI
import AVFoundation
import AVKit

struct CardView: View {
    let asset: AssetSummary
    let photoService: PhotoLibraryService
    let isTopCard: Bool

    /// Drag position for the top card (the deck's live motion) or a departing
    /// card (its fling target); nil for the cards behind. Read only by the
    /// root offset and the stamp overlay, so a drag frame re-renders little.
    var motion: CardMotion? = nil
    /// Incremented by SwipeSessionView's "Zoom" accessibility action; CardView
    /// toggles zoom on change (only the top card receives a non-zero value).
    var zoomToggleRequest: Int = 0
    /// Incremented by the "Play Video" accessibility action: the card's own
    /// Play button is hidden from VoiceOver with the rest of the card.
    var playRequest: Int = 0
    /// Incremented by the "Try Loading Again" accessibility action.
    var retryRequest: Int = 0
    /// Reports whether this card is currently zoomed so the session can
    /// suspend its swipe drag while a pinch/pan is inspecting the photo.
    var onZoomChanged: ((Bool) -> Void)? = nil
    /// Swipe drag relayed from this card's own gesture graph. The drag has to
    /// live here, on the same view as the pinch: a gesture attached to a
    /// descendant view blocks an ancestor's drag outright (measured — the card
    /// did not move a single pixel), and neither `.simultaneousGesture` nor
    /// `.highPriorityGesture` on the ancestor overrides that.
    ///
    /// Both relays carry this card's asset id: an undo can land mid-drag and
    /// put a different card on top, and the deck must drop the gesture rather
    /// than apply it to the wrong photo.
    var onSwipeDragChanged: ((String, CGSize) -> Void)? = nil
    var onSwipeDragEnded: ((String, DragGesture.Value, CGFloat) -> Void)? = nil
    /// Called with the asset id once the card image is on screen. The deck
    /// blocks Delete until then, so the user never deletes a photo they did
    /// not see.
    var onImageShown: ((String) -> Void)? = nil

    @State private var image: UIImage?
    /// The image request returned nothing (an iCloud download failed or
    /// timed out). Shows a retry state instead of an endless shimmer.
    @State private var loadFailed = false
    @State private var isLoadingPlayer = false
    @State private var player: AVPlayer?
    /// The in-flight player-item load, tracked so `stopPlayback` can cancel it:
    /// without cancellation, a load started on the top card would still create
    /// a playing player after the card was swiped away (SWIPE-07).
    @State private var loadTask: Task<Void, Never>?
    /// In-flight card-image load (initial `.task` or retry). Stored so retry
    /// can be serialized and teardown can cancel it; otherwise the initial
    /// load and a retry complete unordered and both write image/loadFailed.
    @State private var imageLoadTask: Task<Void, Never>?
    /// True while loadImage is in flight. Retry is only accepted after failure
    /// (loadFailed) and while not already loading.
    @State private var isLoadingImage = false

    @State private var zoomState = ZoomState()
    /// Higher-resolution decode swapped in while zoomed so inspection stays
    /// sharp past the screen-sized card image (kept nil until first zoom).
    @State private var fullResImage: UIImage?
    @State private var fullResTask: Task<Void, Never>?
    /// Offset captured when the current pan gesture began, so pan deltas
    /// accumulate instead of resetting from zero on each new drag.
    @State private var panStartOffset: CGSize?
    /// Scale captured when the current pinch began, so a second pinch
    /// multiplies from the card's scale instead of snapping back to ~1x
    /// (mirrors `panStartOffset`; `MagnifyGesture` restarts at 1.0).
    @State private var pinchStartScale: CGFloat?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Image — the loading branch carries the same swipe drag so a
                // slow image can't swallow the gesture; zoom/pan stay on the
                // loaded image's own graph below.
                if let image {
                    zoomableImage(image, frame: geometry.size)
                } else if loadFailed {
                    loadFailedView
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .background(Color.cardSurface)
                        .gesture(unifiedDrag(frame: geometry.size))
                } else {
                    SkeletonView(cornerRadius: 0)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .gesture(unifiedDrag(frame: geometry.size))
                }

                // Video playback (SWIPE-07): a play affordance on the top card
                // loads the player item and plays inline; playback stops when the
                // card is dragged or leaves the deck.
                // No Play button over the failed state: it would sit on top of
                // the "Try Again" button.
                if asset.mediaType == .video, isTopCard, !loadFailed {
                    if isLoadingPlayer {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                            .accessibilityLabel("Loading video")
                    } else if let player {
                        VideoPlayer(player: player)
                            .accessibilityLabel("Video preview playing")
                            // The player layer sits above the gesture-bearing
                            // image, so without its own drag a playing card
                            // cannot be swiped. A tap travels zero distance and
                            // fails this drag, so the player's controls stay
                            // tappable.
                            .gesture(unifiedDrag(frame: geometry.size))
                    } else {
                        Button {
                            startPlayback()
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .scaledGlyph(ScaledSize.videoPlayGlyph)
                                .foregroundStyle(.white.opacity(0.9))
                                .shadow(color: .black.opacity(0.4), radius: 6)
                        }
                        .accessibilityLabel("Play video")
                    }
                }

                // Gradient overlay at bottom
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 140)
                }

                // Metadata overlay
                VStack {
                    // Top badges
                    HStack(spacing: Spacing.sm) {
                        if asset.isLivePhoto {
                            BadgeView(text: "LIVE", icon: "livephoto", color: .yellow)
                        }
                        if !asset.isLocallyAvailable {
                            BadgeView(text: "iCloud", icon: "icloud.and.arrow.down", color: .blue)
                        }
                        Spacer()
                        if asset.isFavorite {
                            FavoriteMark(font: .title3)
                        }
                    }
                    .padding(.top, Spacing.lg)
                    .padding(.horizontal, Spacing.lg)

                    Spacer()

                    // Bottom info
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            if asset.mediaType == .video {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "video.fill")
                                        .font(.caption)
                                    Text(asset.formattedDuration)
                                        .font(.caption.monospacedDigit())
                                }
                                .foregroundStyle(.white)
                            }

                            if let date = asset.creationDate {
                                Text(date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }

                        Spacer()

                        Text(asset.displaySize)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
                }

                // Swipe indicators
                if let motion {
                    SwipeStampOverlay(motion: motion)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
            // Shadow cast by a plain shape behind the card, not by the photo
            // content: a content shadow needs an offscreen pass every frame
            // the card moves. The top card gets the fuller shadow.
            .background {
                RoundedRectangle(cornerRadius: CornerRadius.large)
                    .fill(Color.cardSurface)
                    .shadow(color: .black.opacity(isTopCard ? 0.2 : 0.10), radius: isTopCard ? 8 : 3, x: 0, y: 4)
            }
            // Inside the GeometryReader so the accessibility-initiated toggle
            // clamps against the real card frame, not a screen-size proxy.
            .onChange(of: retryRequest) { _, newValue in
                if newValue > 0 { retryLoad() }
            }
            .onChange(of: playRequest) { _, newValue in
                guard newValue > 0, !loadFailed else { return }
                startPlayback()
            }
            .onChange(of: zoomToggleRequest) { _, _ in
                guard zoomToggleRequest > 0 else { return }
                toggleZoom(frame: geometry.size)
            }
        }
        .task {
            await loadImage()
        }
        .onDisappear {
            // The card left the deck — tear down playback so the player item
            // and its buffers aren't retained (SWIPE-07), and drop zoom state
            // plus the full-res decode so inspection memory is released.
            // Also cancel any in-flight image load/retry so a late success
            // can't report onImageShown for a card that left the deck.
            imageLoadTask?.cancel()
            imageLoadTask = nil
            stopPlayback()
            resetZoom()
        }
        .onChange(of: isTopCard) { _, newValue in
            // The card stopped leading the deck (swiped or advanced) — tear
            // down playback AND cancel any in-flight load so a load started on
            // the top card can't finish into a playing player on an off-top
            // card (SWIPE-07). Zoom resets for the same reason: an off-top
            // card must not come back zoomed or report stale zoom upward.
            if !newValue {
                imageLoadTask?.cancel()
                imageLoadTask = nil
                stopPlayback()
                resetZoom()
            }
        }
        .modifier(SwipeMotionEffect(motion: motion))
        .onChange(of: motion?.isDragging ?? false) { _, dragging in
            // The user started dragging the card — stop playback so the video
            // doesn't keep playing under the swipe (SWIPE-07). Keyed on the
            // gesture's own flag, not the offset, which changes every frame.
            if dragging {
                stopPlayback()
            }
        }
        .onChange(of: zoomState.scale) { _, newScale in
            // Sharper decode once actually zoomed (not on sub-threshold pinch
            // noise); abandon the in-flight load if the user backed all the
            // way out before it landed.
            if newScale > 1.2 {
                loadFullResolution()
            } else if newScale <= 1.001, fullResImage == nil {
                fullResTask?.cancel()
                fullResTask = nil
            }
        }
        .onChange(of: zoomState.isZoomed) { _, zoomed in
            // Edge-triggered: reporting per pinch frame rebuilds the whole
            // deck and flips the gesture graph mid-recognition.
            onZoomChanged?(zoomed)
            // The pan member detaches below 1x; a pan caught mid-touch by
            // that teardown never runs onEnded, so drop its captured base —
            // otherwise the next pan reuses a stale base and jumps.
            if !zoomed {
                panStartOffset = nil
                pinchStartScale = nil
            }
        }
    }

    /// The card image plus its gesture graph.
    ///
    /// Swipe and inspect share ONE gesture graph, on this view. That is
    /// deliberate and load-bearing: a gesture attached here (a descendant of the
    /// deck's card slot) takes the touch away from any drag attached further up
    /// the hierarchy. Measured on the simulator, the card did not move a single
    /// pixel during a drag until the finger lifted, and neither
    /// `.simultaneousGesture` nor `.highPriorityGesture` on the ancestor changed
    /// that. So the swipe is relayed to the deck through the drag callbacks
    /// instead of being attached above this view.
    @ViewBuilder
    private func zoomableImage(_ image: UIImage, frame: CGSize) -> some View {
        let base = Image(uiImage: fullResImage ?? image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: frame.width, height: frame.height)
            .clipped()
            // Zoom applies after clipping so the image can grow past the card;
            // the card-level clipShape trims it.
            .scaleEffect(zoomState.scale)
            .offset(zoomState.offset)
            .transition(.opacity)
        // Only the leading card is interactive. The graph is masked off, not
        // removed, on the other cards: swapping view branches on promotion
        // cross-faded the image with itself.
        let mask: GestureMask = isTopCard ? .all : .none

        if asset.mediaType == .video {
            // Videos keep their inline play affordance and can still be swiped.
            base.gesture(unifiedDrag(frame: frame), including: mask)
        } else {
            // One graph for the swipe and the pinch, with the double-tap as a
            // separate simultaneous gesture. This is the shape verified end to
            // end on the simulator: the card tracks the finger during a drag,
            // snaps back on release, commits past the threshold, and a
            // double-tap zooms in and out. Folding the tap in as a third
            // `simultaneously` member is untested, not known-bad.
            base
                .gesture(
                    pinchGesture(frame: frame)
                        .simultaneously(with: unifiedDrag(frame: frame)),
                    including: mask
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded { toggleZoom(frame: frame) },
                    including: mask
                )
        }
    }

    private func loadImage() async {
        // Serialize: a retry while the initial load is still in flight is
        // ignored instead of racing it with two unordered completions.
        guard !isLoadingImage else { return }
        isLoadingImage = true
        defer {
            isLoadingImage = false
            imageLoadTask = nil
        }
        // Full-screen pixel size matches the swipe session's prefetch target so the
        // cached image is reused instead of re-fetched. Avoids deprecated UIScreen.main.
        let loaded = await photoService.loadImage(for: asset.id, targetSize: ScreenMetrics.pixelSize)
        // The card may have left the deck (or been cancelled) while loading —
        // a late success must not show, or report the image as shown off-deck.
        guard !Task.isCancelled else { return }
        withAnimation(.easeIn(duration: 0.3)) {
            image = loaded
            loadFailed = loaded == nil
        }
        if loaded != nil {
            onImageShown?(asset.id)
        }
    }

    private func retryLoad() {
        guard image == nil, loadFailed, !isLoadingImage else { return }
        loadFailed = false
        imageLoadTask?.cancel()
        imageLoadTask = Task { await loadImage() }
    }

    private var loadFailedView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: asset.isLocallyAvailable ? "exclamationmark.triangle" : "icloud.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Couldn't \(asset.isLocallyAvailable ? "load" : "download") this \(asset.mediaType == .video ? "video" : "photo")\(asset.isLocallyAvailable ? "" : " from iCloud").")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("You can keep or skip it. Delete is off until it shows.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: retryLoad)
            .buttonStyle(.bordered)
        }
        .padding(Spacing.xl)
    }

    // MARK: - Zoom Inspection

    /// Pinch relative to the scale captured at gesture start (mirrors the
    /// `panStartOffset` pattern): `MagnifyGesture` reports magnification from
    /// 1.0 on every gesture, so applying it raw snaps a second pinch to ~1x.
    private func pinchGesture(frame: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if pinchStartScale == nil { pinchStartScale = zoomState.scale }
                let content = renderedContentSize(for: frame)
                zoomState.setPinch(
                    base: pinchStartScale ?? 1.0,
                    magnification: value.magnification,
                    frame: frame,
                    contentSize: content
                )
            }
            .onEnded { _ in
                pinchStartScale = nil
                zoomState.endPinch()
            }
    }

    /// One drag serves both interactions, chosen by zoom state rather than by
    /// swapping the gesture graph (which would tear down a live pinch and skip
    /// its `onEnded`):
    /// - unzoomed: relays the swipe to the deck, which owns the commit policy
    /// - zoomed: pans the zoomed photo
    /// Combined with the pinch on the same view so both can recognize.
    /// Global space on purpose: the card moves and rotates under the finger
    /// (and the zoomed image is scaled), so local translations shift every
    /// frame and the card wobbles.
    private func unifiedDrag(frame: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if zoomState.isZoomed {
                    if panStartOffset == nil { panStartOffset = zoomState.offset }
                    zoomState.setPan(
                        base: panStartOffset ?? .zero,
                        translation: value.translation,
                        frame: frame,
                        contentSize: renderedContentSize(for: frame)
                    )
                } else {
                    onSwipeDragChanged?(asset.id, value.translation)
                }
            }
            .onEnded { value in
                if zoomState.isZoomed {
                    panStartOffset = nil
                } else {
                    onSwipeDragEnded?(asset.id, value, frame.width)
                }
            }
    }

    private func toggleZoom(frame: CGSize) {
        guard asset.mediaType != .video else { return }
        let willZoom = !zoomState.isZoomed
        withAnimation(.reduceMotionAware(.spring(response: 0.25, dampingFraction: 0.8), reduceMotion: reduceMotion)) {
            zoomState.toggle(frame: frame, contentSize: renderedContentSize(for: frame))
        }
        if willZoom {
            loadFullResolution()
        }
    }

    private func loadFullResolution() {
        guard asset.mediaType != .video, fullResImage == nil, fullResTask == nil else { return }
        // Target enough pixels to stay sharp at deep zoom, capped so a 48 MP
        // panorama can't decode into ~190 MB of memory. Below the cap, skip
        // entirely when the card image already covers the zoom target.
        // Reference: a 12 MP photo (4032 px wide) against an ~1110 px card image stays native-sharp to ~3.3x; past that it upscales gracefully.
        let maxDimension: CGFloat = 4096
        let width = CGFloat(asset.pixelWidth)
        let height = CGFloat(asset.pixelHeight)
        let longest = max(width, height)
        guard longest > 0 else { return }
        let factor = min(1.0, maxDimension / longest)
        let target = CGSize(width: width * factor, height: height * factor)
        guard target.width > ScreenMetrics.pixelSize.width else { return }
        fullResTask = Task { @MainActor in
            let loaded = await photoService.loadImage(for: asset.id, targetSize: target)
            guard !Task.isCancelled else { return }
            fullResImage = loaded
            // Self-clear so a failed load doesn't poison the guard above and
            // block every later retry for this card's lifetime.
            fullResTask = nil
        }
    }

    private func resetZoom() {
        fullResTask?.cancel()
        fullResTask = nil
        fullResImage = nil
        panStartOffset = nil
        pinchStartScale = nil
        if zoomState.isZoomed {
            zoomState.reset()
            onZoomChanged?(false)
        }
    }

    /// Aspect-fill rendered size of the photo in the card frame: the image
    /// covers the frame, so one axis already overflows at 1x. Pan limits must
    /// use this, not the frame, or zoomed content edges stay unreachable.
    private func renderedContentSize(for frame: CGSize) -> CGSize {
        let aspect = CGFloat(asset.pixelWidth) / CGFloat(max(asset.pixelHeight, 1))
        guard aspect.isFinite, aspect > 0, frame.height > 0 else { return frame }
        if aspect > frame.width / frame.height {
            return CGSize(width: frame.height * aspect, height: frame.height)
        } else {
            return CGSize(width: frame.width, height: frame.width / aspect)
        }
    }

    private func startPlayback() {
        guard player == nil, isTopCard, !loadFailed else { return }
        loadTask?.cancel()
        isLoadingPlayer = true
        loadTask = Task { @MainActor in
            let box = await photoService.loadPlayerItem(for: asset.id)
            // A cancelled load must not hide the spinner of a newer one. The
            // card may also have been swiped away while the item was loading;
            // the isTopCard/drag/disappear teardowns above cancel this task,
            // so no playing player is created off-screen.
            guard !Task.isCancelled else { return }
            isLoadingPlayer = false
            // A nil item (iCloud download failed) puts the Play button back
            // so the user can try again.
            guard let box else { return }
            let newPlayer = AVPlayer(playerItem: box.value)
            player = newPlayer
            newPlayer.play()
        }
    }

    private func stopPlayback() {
        loadTask?.cancel()
        loadTask = nil
        isLoadingPlayer = false
        player?.pause()
        player = nil
    }
}

/// DELETE / KEEP / ALBUM stamps and tints, driven by the card's drag. Its own
/// view so a drag frame re-evaluates only this and the root offset.
private struct SwipeStampOverlay: View {
    let motion: CardMotion

    private var deleteOpacity: Double { min(max(-Double(motion.offset.width) / 150.0, 0), 1.0) }
    private var keepOpacity: Double { min(max(Double(motion.offset.width) / 150.0, 0), 1.0) }
    private var albumOpacity: Double { min(max(-Double(motion.offset.height) / 150.0, 0), 1.0) }

    var body: some View {
        ZStack {
            VStack {
                HStack {
                    Spacer()
                    Label("DELETE", systemImage: "trash.fill")
                        .font(.title.bold())
                        .foregroundStyle(.red)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.small)
                                .stroke(.red, lineWidth: 3)
                        )
                        .rotationEffect(.degrees(15))
                        .padding(.trailing, Spacing.xxl)
                        .padding(.top, 40)
                }
                Spacer()
            }
            .opacity(deleteOpacity)

            VStack {
                HStack {
                    Label("KEEP", systemImage: "checkmark")
                        .font(.title.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.small)
                                .stroke(.green, lineWidth: 3)
                        )
                        .rotationEffect(.degrees(-15))
                        .padding(.leading, Spacing.xxl)
                        .padding(.top, 40)
                    Spacer()
                }
                Spacer()
            }
            .opacity(keepOpacity)

            // Up-drag: file into an album (SwipeSessionView's up-swipe
            // gesture) — mirrors the DELETE/KEEP direction stamps.
            VStack {
                Label("ALBUM", systemImage: "folder.badge.plus")
                    .font(.title3.bold())
                    .foregroundStyle(.blue)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.small)
                            .stroke(.blue, lineWidth: 3)
                    )
                    .padding(.top, 40)
                Spacer()
            }
            .opacity(albumOpacity)

            Rectangle()
                .fill(.red.opacity(deleteOpacity * 0.15))
            Rectangle()
                .fill(.green.opacity(keepOpacity * 0.15))
        }
        .allowsHitTesting(false)
    }
}

/// Moves and tilts the card with its drag. A modifier so the per-frame read
/// of `motion.offset` re-evaluates only this, not the card's body.
private struct SwipeMotionEffect: ViewModifier {
    let motion: CardMotion?

    func body(content: Content) -> some View {
        let offset = motion?.offset ?? .zero
        content
            .offset(offset)
            .rotationEffect(.degrees(Double(offset.width / 20)))
    }
}

struct BadgeView: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2.bold())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(color.opacity(0.7))
        .clipShape(Capsule())
    }
}
