import SwiftUI
import AVFoundation
import AVKit

struct CardView: View {
    let asset: AssetSummary
    let photoService: PhotoLibraryService
    let isTopCard: Bool

    var dragOffset: CGSize = .zero
    /// Incremented by SwipeSessionView's "Zoom" accessibility action; CardView
    /// toggles zoom on change (only the top card receives a non-zero value).
    var zoomToggleRequest: Int = 0
    /// Reports whether this card is currently zoomed so the session can
    /// suspend its swipe drag while a pinch/pan is inspecting the photo.
    var onZoomChanged: ((Bool) -> Void)? = nil

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    /// The in-flight player-item load, tracked so `stopPlayback` can cancel it:
    /// without cancellation, a load started on the top card would still create
    /// a playing player after the card was swiped away (SWIPE-07).
    @State private var loadTask: Task<Void, Never>?

    @State private var zoomState = ZoomState()
    /// Higher-resolution decode swapped in while zoomed so inspection stays
    /// sharp past the screen-sized card image (kept nil until first zoom).
    @State private var fullResImage: UIImage?
    @State private var fullResTask: Task<Void, Never>?
    /// Offset captured when the current pan gesture began, so pan deltas
    /// accumulate instead of resetting from zero on each new drag.
    @State private var panStartOffset: CGSize?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var deleteOpacity: Double {
        guard isTopCard else { return 0 }
        return min(max(-Double(dragOffset.width) / 150.0, 0), 1.0)
    }

    private var keepOpacity: Double {
        guard isTopCard else { return 0 }
        return min(max(Double(dragOffset.width) / 150.0, 0), 1.0)
    }

    private var albumOpacity: Double {
        guard isTopCard else { return 0 }
        return min(max(-Double(dragOffset.height) / 150.0, 0), 1.0)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Image
                if let image {
                    Image(uiImage: fullResImage ?? image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        // Zoom applies after clipping so the image can grow
                        // past the card; the card-level clipShape trims it.
                        .scaleEffect(zoomState.scale)
                        .offset(zoomState.offset)
                        .transition(.opacity)
                        // Pinch to inspect (photos only — videos keep their
                        // play/fullscreen flow). One static gesture graph: the
                        // pan member never recognizes while unzoomed (infinite
                        // threshold), so single-finger drags still reach the
                        // session's swipe drag; while zoomed that drag is
                        // nil'd and the pan owns the touch.
                        .gesture(
                            asset.mediaType != .video
                                ? pinchGesture(frame: geometry.size)
                                    .simultaneously(with: panGesture(frame: geometry.size))
                                : nil
                        )
                        .onTapGesture(count: 2) {
                            guard asset.mediaType != .video else { return }
                            toggleZoom(frame: geometry.size)
                        }
                } else {
                    SkeletonView(cornerRadius: 0)
                }

                // Video playback (SWIPE-07): a play affordance on the top card
                // loads the player item and plays inline; playback stops when the
                // card is dragged or leaves the deck.
                if asset.mediaType == .video, isTopCard {
                    if let player {
                        VideoPlayer(player: player)
                            .accessibilityLabel("Video preview playing")
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
                if isTopCard {
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
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
            .cardShadow()
            // Inside the GeometryReader so the accessibility-initiated toggle
            // clamps against the real card frame, not a screen-size proxy.
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
                stopPlayback()
                resetZoom()
            }
        }
        .onChange(of: dragOffset) { _, newValue in
            // The user started dragging the card — stop playback so the video
            // doesn't keep playing under the swipe (SWIPE-07).
            if newValue != .zero {
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
            }
        }
    }

    private func loadImage() async {
        // Full-screen pixel size matches the swipe session's prefetch target so the
        // cached image is reused instead of re-fetched. Avoids deprecated UIScreen.main.
        let loaded = await photoService.loadImage(for: asset.id, targetSize: ScreenMetrics.pixelSize)
        withAnimation(.easeIn(duration: 0.3)) {
            image = loaded
        }
    }

    // MARK: - Zoom Inspection

    /// Cumulative pinch — `MagnifyGesture` reports total magnification from
    /// gesture start, so each update is absolute (no start-scale bookkeeping).
    private func pinchGesture(frame: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                let content = renderedContentSize(for: frame)
                zoomState.setScale(value.magnification, frame: frame, contentSize: content)
            }
            .onEnded { _ in
                zoomState.endPinch()
            }
    }

    private func panGesture(frame: CGSize) -> some Gesture {
        // Infinite threshold while unzoomed: the gesture never recognizes, so
        // it cannot steal single-finger drags from the swipe deck. Only this
        // threshold value flips on zoom transitions — never the graph shape —
        // so a live pinch is never disturbed.
        DragGesture(minimumDistance: zoomState.isZoomed ? 1.0 : .infinity)
            .onChanged { value in
                guard zoomState.isZoomed else { return }
                if panStartOffset == nil { panStartOffset = zoomState.offset }
                let content = renderedContentSize(for: frame)
                zoomState.setPan(base: panStartOffset ?? .zero, translation: value.translation, frame: frame, contentSize: content)
            }
            .onEnded { _ in
                panStartOffset = nil
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
        guard player == nil, isTopCard else { return }
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            guard let box = await photoService.loadPlayerItem(for: asset.id) else { return }
            // The card may have been swiped away while the item was loading;
            // the isTopCard/drag/disappear teardowns above cancel this task —
            // respect that instead of creating a playing player off-screen.
            guard !Task.isCancelled else { return }
            let newPlayer = AVPlayer(playerItem: box.value)
            player = newPlayer
            newPlayer.play()
        }
    }

    private func stopPlayback() {
        loadTask?.cancel()
        loadTask = nil
        player?.pause()
        player = nil
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
