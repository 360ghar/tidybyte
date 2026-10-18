import SwiftUI
import AVFoundation
import AVKit

/// Image-request policy for one swipe card: how many pixels to ask for, and
/// when a resize invalidates the decode that is already on screen.
///
/// Pure value logic so both rules are unit-testable. The alternative proof —
/// folding the device mid-session — needs a foldable runtime, which is not
/// installed in this environment.
enum CardImageRequest {
    /// Floor for every request. Both inputs can be unmeasured on the first
    /// layout pass (the deck has not published a target, the card has not
    /// reported its frame), and a `.zero` target is a degenerate
    /// `PHImageManager` request that can return nothing at all. 64 px is far
    /// below any real card, and the true target replaces it on the next pass.
    static let minimumPixels: CGFloat = 64

    /// Targets within this many pixels of each other are the same decode. The
    /// deck's rect and a card's rect are one rect reported by two geometry
    /// observers, so they can differ in the last fraction of a point; without
    /// the tolerance that rounding would trigger a redundant reload whose only
    /// effect is a second cached lookup.
    static let targetTolerance: CGFloat = 0.5

    /// Pixel size to request this card's image at. The deck's published target
    /// is preferred: the session prefetches the same pixels, so one decode
    /// serves both. Before the deck has measured itself, this card's own frame
    /// is the same rect (the deck forces every card to its own size), so the
    /// fallback cannot disagree with it. Either way the result is floored, so a
    /// request is never degenerate.
    static func size(deckTarget: CGSize, frame: CGSize, displayScale: CGFloat) -> CGSize {
        let target = deckTarget != .zero
            ? deckTarget
            : CGSize(width: frame.width * displayScale, height: frame.height * displayScale)
        return CGSize(
            width: max(target.width, minimumPixels),
            height: max(target.height, minimumPixels)
        )
    }

    /// Whether the on-screen image is stale because the render target moved
    /// under it. False when nothing is on screen yet (the first load is the
    /// `.task`'s job), false for an unmeasured target, and false when the
    /// target is the one the visible image was decoded at — so an ordinary
    /// layout pass, which republishes the same target, cannot restart the load.
    static func shouldReload(
        currentTarget: CGSize,
        lastRequestedTarget: CGSize,
        hasImage: Bool
    ) -> Bool {
        guard hasImage, currentTarget != .zero else { return false }
        return abs(currentTarget.width - lastRequestedTarget.width) > targetTolerance
            || abs(currentTarget.height - lastRequestedTarget.height) > targetTolerance
    }
}

struct CardView: View {
    let asset: AssetSummary
    let photoService: PhotoLibraryService
    let isTopCard: Bool
    /// Pixel size of this card's render area, published by `SwipeCardDeck`
    /// (deck size × display scale). The session prefetch requests the same
    /// pixels, so the card's own load reuses that cached decode instead of
    /// fetching its own. `.zero` until the deck has measured itself, in which
    /// case this card's own frame is the same rect (see `pixelTarget(for:)`).
    var renderTarget: CGSize = .zero
    var reviewReason: String? = nil

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
    var onSwipeDragEnded: ((String, DragGesture.Value, CGSize) -> Void)? = nil
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

    /// This card's own frame, tracked so the non-body call sites (the full-res
    /// swap) and a live resize can work from the current rect rather than a
    /// captured one.
    @State private var cardFrame: CGSize = .zero
    /// The render target the image on screen was decoded at. `.zero` until the
    /// first load lands; compared against the deck's live target so a resize
    /// re-requests the decode instead of leaving the visible photo soft until
    /// the card leaves the deck.
    @State private var loadedTarget: CGSize = .zero

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Pixel density of this card's window, for the image request size. From
    /// the environment, so it follows the window instead of the screen.
    @Environment(\.displayScale) private var displayScale

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

                    if isTopCard, let reviewReason {
                        Text(reviewReason)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(Spacing.sm)
                            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: CornerRadius.small))
                            .padding(.horizontal, Spacing.lg)
                    }
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
            // The load lives inside the reader because its target is this card's
            // own frame: issuing it from outside would race the first layout and
            // could request a zero-size image.
            .task {
                await loadImage(frame: geometry.size)
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
                cardFrame = newSize
                reflowZoom(to: newSize)
            }
        }
        .onChange(of: renderTarget) { _, newTarget in
            // The deck resized and republished its render target: the image on
            // screen was decoded for the old rect, so fetch the new one now
            // rather than leaving it soft until the card leaves the deck.
            reloadImageIfTargetMoved(to: newTarget)
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

    private func loadImage(frame: CGSize) async {
        // Serialize: a retry while the initial load is still in flight is
        // ignored instead of racing it with two unordered completions.
        guard !isLoadingImage else { return }
        isLoadingImage = true
        defer {
            isLoadingImage = false
            imageLoadTask = nil
        }
        var requested = pixelTarget(for: frame)
        while true {
            // Card-sized pixels, the same target the session prefetches, so the
            // cached decode is reused instead of re-fetched.
            let loaded = await photoService.loadImage(for: asset.id, targetSize: requested)
            // The card may have left the deck (or been cancelled) while loading —
            // a late success must not show, or report the image as shown off-deck.
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) {
                image = loaded
                loadFailed = loaded == nil
            }
            if loaded != nil {
                loadedTarget = requested
                onImageShown?(asset.id)
            }
            // A resize that landed while the request was in flight (a fold,
            // unfold, or any container change) leaves the image decoded for the
            // old rect. Re-request the target the card renders at now, inside
            // this same task, rather than waiting for the card to leave the
            // deck. This also covers a resize that arrives between the deck's
            // republish and this check, which the `renderTarget` observer alone
            // would drop while `isLoadingImage` was set.
            let current = pixelTarget(for: cardFrame)
            guard CardImageRequest.shouldReload(
                currentTarget: current,
                lastRequestedTarget: requested,
                hasImage: loaded != nil
            ) else { return }
            requested = current
        }
    }

    /// Re-requests the image when a resize moved the render target under an
    /// already-displayed one. Silent while nothing is on screen (the first load
    /// owns that) and while a load is in flight (that load's own loop re-checks
    /// the target when it lands), so an ordinary layout pass — which republishes
    /// the same target — cannot restart anything. A failed load is left to the
    /// user's Try Again, exactly as before.
    private func reloadImageIfTargetMoved(to newTarget: CGSize) {
        guard CardImageRequest.shouldReload(
            currentTarget: newTarget,
            lastRequestedTarget: loadedTarget,
            hasImage: image != nil
        ) else { return }
        imageLoadTask?.cancel()
        imageLoadTask = Task { await loadImage(frame: cardFrame) }
    }

    private func retryLoad() {
        guard image == nil, loadFailed, !isLoadingImage else { return }
        loadFailed = false
        imageLoadTask?.cancel()
        // The card has been on screen (and so measured) since the first attempt.
        imageLoadTask = Task { await loadImage(frame: cardFrame) }
    }

    /// The failure headline, as four whole sentences rather than one assembled
    /// from fragments.
    ///
    /// The original built it from five pieces (`"load"`, `"video"`, `" from
    /// iCloud"`, …) interpolated into `"Couldn't %@ this %@%@."`. That template
    /// is in the catalog, so it *looks* localized, but its German form is
    /// `"%@ dieses %@%@ nicht möglich."` — the fragments go in unchanged, so a
    /// German user read "load dieses video nicht möglich." No language can
    /// reorder a sentence it never sees whole.
    private var loadFailureMessage: String {
        switch (asset.isLocallyAvailable, asset.mediaType == .video) {
        case (true, false): L10n.string("Couldn't load this photo.")
        case (true, true): L10n.string("Couldn't load this video.")
        case (false, false): L10n.string("Couldn't download this photo from iCloud.")
        case (false, true): L10n.string("Couldn't download this video from iCloud.")
        }
    }

    private var loadFailedView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: asset.isLocallyAvailable ? "exclamationmark.triangle" : "icloud.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(loadFailureMessage)
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
                    onSwipeDragEnded?(asset.id, value, frame)
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
        // Upsample gate: both sides are the card's own render size now, so a
        // deck that is short or narrow relative to the screen can no longer
        // disable the swap and leave deep zoom soft.
        guard target.width > pixelTarget(for: cardFrame).width else { return }
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

    /// Pixel size to request this card's image at. See `CardImageRequest` for
    /// the deck-target preference, the frame fallback, and the floor that keeps
    /// a first-layout request from being degenerate.
    private func pixelTarget(for frame: CGSize) -> CGSize {
        CardImageRequest.size(deckTarget: renderTarget, frame: frame, displayScale: displayScale)
    }

    /// A live resize (fold/unfold, Split View, Stage Manager) invalidates the
    /// frame the zoom offset was clamped against — a pan can be left hanging
    /// past an edge the card no longer has. Re-clamp against the new frame, and
    /// drop the captured gesture bases so a pan straddling the resize restarts
    /// from the re-clamped offset instead of adding deltas measured in the old
    /// frame. Scale is untouched (the photo is not resized, the card is).
    private func reflowZoom(to frame: CGSize) {
        guard zoomState.isZoomed else { return }
        panStartOffset = nil
        pinchStartScale = nil
        zoomState.setScale(zoomState.scale, frame: frame, contentSize: renderedContentSize(for: frame))
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
