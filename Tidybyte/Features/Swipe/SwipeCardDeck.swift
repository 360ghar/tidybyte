import SwiftUI

// SwipeCardDeck: the swappable card stack and its action bar, extracted from
// SwipeSessionView so a drag frame re-renders only the deck. `dragOffset` used
// to be @State on SwipeSessionView, which meant every drag frame re-ran the
// whole session body (progress bar, both toolbars, the ViewThatFits action bar,
// toast, safeAreaInset, plus the 3-card ForEach).
//
// Animation contract: the drag writes `dragOffset` OUTSIDE any withAnimation so
// the card tracks the finger 1:1. Every intended animation (snap-back, zoom
// reset, commit fling, post-fling reset) supplies its own explicit animation.
struct SwipeCardDeck: View {
    @Bindable var viewModel: SwipeSessionViewModel
    /// Surfaces the "marked for deletion — tap Undo" hint in the parent's toast.
    var onUndoHint: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var swipeTask: Task<Void, Never>?
    /// True while the top card is pinch-zoomed: the swipe drag yields so a
    /// one-finger drag pans the photo instead of committing a swipe.
    @State private var isTopCardZoomed = false
    /// Monotonic counter driving CardView's "Zoom" accessibility action.
    @State private var zoomToggleRequest = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Card stack — capped to a phone-like width and centered so a single
            // card doesn't span the full width of an iPad. The cap is a no-op on
            // iPhone (screen is narrower than 560pt), preserving the 16pt inset.
            cardStack
                .readableWidth(560)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            // Action buttons
            actionBar
                .padding(.top, 12)
                .padding(.bottom, 8)
        }
        .onAppear {
            // Warm the Taptic Engine so the drag-start impact is not the one
            // that pays for spinning it up.
            HapticHelper.prepare(.light)
            HapticHelper.prepare(.heavy)
        }
        .onChange(of: viewModel.currentIndex) {
            // The deck advanced (swipe/skip/undo/album confirm) — the deck owns
            // the zoom flag, so clear it here rather than trusting the outgoing
            // card's callback (whose onZoomChanged prop is already nil by
            // teardown time). Resetting the request counter also stops a
            // promoted card from re-firing a stale VoiceOver zoom request.
            // Deliberately UNANIMATED: the incoming card must read the
            // already-zero offset instead of animating in from the outgoing
            // card's flung-off position.
            isTopCardZoomed = false
            zoomToggleRequest = 0
            dragOffset = .zero
            isDragging = false
        }
        .onChange(of: isTopCardZoomed) {
            // Zoom engaged mid-swipe-drag: the in-flight drag tears down
            // without onEnded, so snap the card back instead of leaving it
            // tilted with no swipe committed.
            if isTopCardZoomed {
                withAnimation(.reduceMotionAware(.spring(response: 0.4, dampingFraction: 0.7), reduceMotion: reduceMotion)) {
                    dragOffset = .zero
                }
                isDragging = false
            }
        }
        .onDisappear {
            swipeTask?.cancel()
        }
    }

    // MARK: - Card Stack

    private var cardStack: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(viewModel.visibleCards.enumerated().reversed()), id: \.element.id) { index, asset in
                    let isTop = index == 0
                    let scale = 1.0 - CGFloat(index) * 0.05
                    let yOffset = CGFloat(index) * 10

                    CardView(
                        asset: asset,
                        photoService: viewModel.photoService,
                        isTopCard: isTop,
                        dragOffset: isTop ? dragOffset : .zero,
                        isDragging: isTop && isDragging,
                        zoomToggleRequest: isTop ? zoomToggleRequest : 0,
                        onZoomChanged: isTop ? { isTopCardZoomed = $0 } : nil,
                        onSwipeDragChanged: handleDragChanged,
                        onSwipeDragEnded: handleDragEnded
                    )
                    .scaleEffect(isTop ? 1.0 : scale)
                    .offset(y: isTop ? 0 : yOffset)
                    .offset(x: isTop ? dragOffset.width : 0, y: isTop ? dragOffset.height : 0)
                    .rotationEffect(isTop ? .degrees(Double(dragOffset.width / 20)) : .zero)
                    // No `.gesture` here on purpose. A drag attached above
                    // CardView is starved: the card's own pinch holds the touch
                    // and the deck never sees `onChanged`, so the card sits still
                    // until the finger lifts. `.simultaneousGesture` and
                    // `.highPriorityGesture` here did not change that. The swipe
                    // is relayed from CardView's gesture graph instead.
                    .allowsHitTesting(isTop && !viewModel.isPerformingMutation)
                    .accessibilityElement(children: .ignore)
                    .accessibilityHidden(!isTop)
                    .accessibilityLabel(isTop ? accessibilityLabel(for: asset) : Text(""))
                    .accessibilityActions {
                        if isTop {
                            Button("Delete") { triggerDelete() }
                            Button("Keep") { triggerKeep() }
                            Button("Add to Album") { triggerKeepWithAlbum() }
                            Button("Skip") { viewModel.skip() }
                            if asset.mediaType != .video {
                                Button(isTopCardZoomed ? "Zoom Out" : "Zoom In") {
                                    zoomToggleRequest += 1
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    // MARK: - Swipe Drag (relayed from CardView)

    /// Relay for the top card's drag. The gesture itself lives on `CardView`
    /// (see `unifiedDrag`), because a drag attached anywhere above it is starved
    /// of every `onChanged` by the card's own pinch.
    private func handleDragChanged(_ translation: CGSize) {
        guard !viewModel.isPerformingMutation, !viewModel.isSwiping else { return }
        if !isDragging {
            isDragging = true
            HapticHelper.impact(.light)
        }
        dragOffset = translation
    }

    /// Relay for the top card's drag end. Owns the commit policy: threshold,
    /// velocity, and the horizontal-before-vertical resolution.
    private func handleDragEnded(_ value: DragGesture.Value, cardWidth: CGFloat) {
        isDragging = false
        // A pinch can zoom the card mid-drag (the drag was already in flight
        // when the touch began) — snap back instead of committing a swipe the
        // user replaced with an inspection.
        guard !isTopCardZoomed else {
            withAnimation(.reduceMotionAware(.spring(response: 0.4, dampingFraction: 0.7), reduceMotion: reduceMotion)) {
                dragOffset = .zero
            }
            return
        }
        let threshold = cardWidth * 0.4
        let velocityThreshold: CGFloat = 500
        let predictedWidth = value.predictedEndTranslation.width
        let predictedHeight = value.predictedEndTranslation.height

        // Horizontal checks come first so an ambiguous diagonal drag
        // resolves to keep/delete, not the album picker — the up-swipe
        // only wins when the vertical motion is unambiguous.
        if value.translation.width > threshold || predictedWidth > velocityThreshold {
            // Swipe right — keep
            HapticHelper.impact(.heavy)
            performSwipeAnimation(offset: CGSize(width: 1000, height: value.translation.height)) {
                viewModel.swipeRight()
            }
        } else if value.translation.width < -threshold || predictedWidth < -velocityThreshold {
            // Swipe left — delete
            HapticHelper.impact(.heavy)
            performSwipeAnimation(offset: CGSize(width: -1000, height: value.translation.height)) {
                viewModel.swipeLeft()
                onUndoHint()
            }
        } else if value.translation.height < -threshold || predictedHeight < -velocityThreshold {
            // Swipe up — file this photo into an album. Explicit intent:
            // the picker opens and the card stays until the choice resolves.
            HapticHelper.impact(.heavy)
            performSwipeAnimation(offset: CGSize(width: value.translation.width, height: -1000)) {
                viewModel.keepWithAlbum()
            }
        } else {
            // Snap back
            withAnimation(.reduceMotionAware(.spring(response: 0.4, dampingFraction: 0.7), reduceMotion: reduceMotion)) {
                dragOffset = .zero
            }
        }
    }

    // MARK: - Accessibility / Actions

    private func accessibilityLabel(for asset: AssetSummary) -> Text {
        var parts: [String] = [asset.mediaType == .video ? "Video" : "Photo"]
        if let date = asset.creationDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        parts.append(asset.displaySize)
        if asset.isFavorite { parts.append("Favorite") }
        if asset.isLivePhoto { parts.append("Live Photo.") }
        if !asset.isLocallyAvailable { parts.append("In iCloud.") }
        return Text(parts.joined(separator: ", "))
    }

    private func triggerDelete() {
        guard viewModel.hasMoreCards, !viewModel.isPerformingMutation else { return }
        HapticHelper.impact(.heavy)
        performSwipeAnimation(offset: CGSize(width: -1000, height: 0)) {
            viewModel.swipeLeft()
            onUndoHint()
        }
    }

    private func triggerKeep() {
        guard viewModel.hasMoreCards, !viewModel.isPerformingMutation else { return }
        HapticHelper.impact(.heavy)
        performSwipeAnimation(offset: CGSize(width: 1000, height: 0)) {
            viewModel.swipeRight()
        }
    }

    private func triggerKeepWithAlbum() {
        guard viewModel.hasMoreCards, !viewModel.isPerformingMutation else { return }
        HapticHelper.impact(.heavy)
        performSwipeAnimation(offset: CGSize(width: 0, height: -1000)) {
            viewModel.keepWithAlbum()
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        // The four controls are fixed-diameter circles, so at accessibility text
        // sizes their scaled diameters can exceed the screen width. `ViewThatFits`
        // picks the roomiest spacing that still fits rather than letting the row
        // clip the outer buttons — which is what a fixed 32pt spacing did once the
        // buttons grew.
        ViewThatFits(in: .horizontal) {
            actionBarRow(spacing: 32)
            actionBarRow(spacing: Spacing.lg)
            actionBarRow(spacing: Spacing.md)
            actionBarRow(spacing: Spacing.xs)
        }
        // isSwiping included so Skip can't advance the deck mid-animation
        // while the queued gesture would act on the wrong card (B1).
        .disabled(!viewModel.hasMoreCards || viewModel.isPerformingMutation || viewModel.isSwiping)
    }

    private func actionBarRow(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            // Delete button
            Button {
                triggerDelete()
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .scaledSquare(ScaledSize.actionButton)
                    .background(.red)
                    .clipShape(Circle())
                    .shadow(color: .red.opacity(0.3), radius: 8)
            }
            .keyboardShortcut(.delete, modifiers: [])
            .accessibilityLabel("Delete")
            .accessibilityHint("Marks this photo for deletion and shows the next one")

            // Info / Skip button
            Button {
                HapticHelper.impact(.light)
                viewModel.skip()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .scaledSquare(ScaledSize.secondaryActionButton)
                    .background(Color(.systemGray))
                    .clipShape(Circle())
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .accessibilityLabel("Skip")
            .accessibilityHint("Leaves this photo unchanged and shows the next one")

            // Add to Album button — same as an up-swipe
            Button {
                triggerKeepWithAlbum()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .scaledSquare(ScaledSize.secondaryActionButton)
                    .background(.blue)
                    .clipShape(Circle())
            }
            .keyboardShortcut(.upArrow, modifiers: [])
            .accessibilityLabel("Add to Album")
            .accessibilityHint("Opens the album picker to file this photo")

            // Keep button
            Button {
                triggerKeep()
            } label: {
                Image(systemName: "checkmark")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .scaledSquare(ScaledSize.actionButton)
                    .background(.green)
                    .clipShape(Circle())
                    .shadow(color: .green.opacity(0.3), radius: 8)
            }
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityLabel("Keep")
            .accessibilityHint("Keeps this photo without prompting")
        }
    }

    // MARK: - Swipe Animation

    private func performSwipeAnimation(
        offset: CGSize,
        action: @escaping @MainActor () async -> Void
    ) {
        // Serialize swipes: a second gesture during the animation window is
        // ignored instead of racing the in-flight task (SWIPE-05). The slot
        // guarantee means no task can be in flight here, so no cancel needed.
        guard !viewModel.isPerformingMutation, viewModel.beginSwipeAnimation() else { return }
        withAnimation(.reduceMotionAware(.spring(response: 0.3, dampingFraction: 0.8), reduceMotion: reduceMotion)) {
            dragOffset = offset
        }

        swipeTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else {
                viewModel.endSwipeAnimation()
                return
            }
            await MainActor.run {
                // Only reset the offset if the drag actually ended — resetting
                // mid-gesture yanks the card back from under a new drag (SWIPE-05).
                // The reset needs its own animation now that the removed
                // per-frame `.animation(value: dragOffset)` no longer supplies
                // one: the up-swipe album path does NOT advance currentIndex, so
                // nothing else animates the card back and it would stay flung
                // off-screen while the album picker is up.
                if !isDragging {
                    withAnimation(.reduceMotionAware(.spring(response: 0.4, dampingFraction: 0.7), reduceMotion: reduceMotion)) {
                        dragOffset = .zero
                    }
                }
            }
            await action()
            viewModel.endSwipeAnimation()
        }
    }
}
