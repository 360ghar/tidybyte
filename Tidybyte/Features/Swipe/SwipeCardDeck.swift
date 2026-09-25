import SwiftUI

/// Live drag position of one card. A reference type so a drag frame
/// invalidates only the views that read `offset` (the top card), not the
/// deck body, its action bar, or the cards behind.
@Observable
@MainActor
final class CardMotion {
    var offset: CGSize
    var isDragging = false

    init(offset: CGSize = .zero) {
        self.offset = offset
    }
}

/// What a swipe does, and where the card flies when it commits.
enum SwipeDirection: Equatable {
    case delete, keep, album, skip

    /// Fraction of the card width a drag must travel to commit.
    static let commitFraction: CGFloat = 0.4
    /// Predicted end translation (pt) that commits a short, fast flick.
    static let flickThreshold: CGFloat = 500

    /// The commit policy for a released drag; nil snaps the card back.
    /// Horizontal checks come first so an ambiguous diagonal drag resolves to
    /// keep/delete, not the album picker — the up-swipe only wins when the
    /// vertical motion is unambiguous.
    static func resolve(translation: CGSize, predicted: CGSize, cardWidth: CGFloat) -> SwipeDirection? {
        let threshold = cardWidth * commitFraction
        if translation.width > threshold || predicted.width > flickThreshold { return .keep }
        if translation.width < -threshold || predicted.width < -flickThreshold { return .delete }
        if translation.height < -threshold || predicted.height < -flickThreshold { return .album }
        return nil
    }

    /// Off-screen end point for a card leaving in this direction, keeping the
    /// cross-axis position it was released at. Skip leaves downward, matching
    /// its down-arrow key.
    func flingOffset(from start: CGSize, distance: CGFloat) -> CGSize {
        switch self {
        case .keep: CGSize(width: distance, height: start.height)
        case .delete: CGSize(width: -distance, height: start.height)
        case .album: CGSize(width: start.width, height: -distance)
        case .skip: CGSize(width: start.width, height: distance)
        }
    }

    /// Release velocity expressed the way SwiftUI springs take it: fractions
    /// of the remaining travel per second, along the travel direction. Lets
    /// the fling carry the finger's speed instead of restarting from rest.
    static func relativeVelocity(_ velocity: CGSize, from start: CGSize, to target: CGSize) -> Double {
        let dx = target.width - start.width
        let dy = target.height - start.height
        let distance = hypot(dx, dy)
        guard distance > 1 else { return 0 }
        let along = (velocity.width * dx + velocity.height * dy) / distance
        return min(max(along / distance, 0), 10)
    }
}

// SwipeCardDeck: the swappable card stack and its action bar.
//
// Commit contract: a swipe applies its decision to the view model AT ONCE, so
// the next card is live immediately and a fast second swipe is never dropped.
// The outgoing card stays in the same ForEach (same id, so its image is not
// reloaded) as a "departing" card, flies off, and is removed when its
// animation completes. The drag writes `motion.offset` outside any animation
// so the card tracks the finger 1:1.
struct SwipeCardDeck: View {
    @Bindable var viewModel: SwipeSessionViewModel
    /// Surfaces the "marked for deletion — tap Undo" hint in the parent's toast.
    /// Called with the id of the photo just marked for deletion, so the
    /// toast's Undo can check it still undoes that photo.
    var onUndoHint: (String) -> Void
    /// Called when a delete is refused because the photo never showed.
    var onDeleteBlocked: () -> Void = {}

    /// One rendered card: `depth` 0 is the top card, nil a departing one.
    private struct DeckSlot: Identifiable {
        let asset: AssetSummary
        let depth: Int?
        let motion: CardMotion?
        var id: String { asset.id }
    }

    @State private var motion = CardMotion()
    @State private var departing: [DeckSlot] = []
    /// The card parked on top while the album picker is open. Filing is an
    /// explicit choice, so the card waits for the picker instead of flying off;
    /// when the choice lands the deck flings it out like any other decision, so
    /// its exit animates instead of vanishing.
    @State private var albumCardPending: AssetSummary?
    @State private var deckSize: CGSize = .zero
    /// True while the top card is pinch-zoomed: the swipe drag yields so a
    /// one-finger drag pans the photo instead of committing a swipe.
    @State private var isTopCardZoomed = false
    /// Monotonic counter driving CardView's "Zoom" accessibility action.
    @State private var zoomToggleRequest = 0
    @State private var playRequest = 0
    @State private var retryRequest = 0
    /// Ids of cards whose image is on screen. Delete stays off for a card that
    /// never showed its photo (still loading, or the iCloud download failed).
    @State private var shownAssetIds: Set<String> = []

    private var canDeleteTopCard: Bool {
        guard let id = viewModel.currentAsset?.id else { return false }
        return shownAssetIds.contains(id)
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Far enough that a card, rotated, clears the screen from the deck center.
    private var flingDistance: CGFloat {
        deckSize == .zero ? 1000 : deckSize.width + deckSize.height
    }

    /// Stack (back to front) then departing cards on top. A card that is both
    /// visible and still departing (undo mid-fling) renders as visible.
    private var slots: [DeckSlot] {
        let visible = viewModel.visibleCards
        let visibleIds = Set(visible.map(\.id))
        let stack = visible.enumerated().reversed().map { index, asset in
            DeckSlot(asset: asset, depth: index, motion: index == 0 ? motion : nil)
        }
        return stack + departing.filter { !visibleIds.contains($0.id) }
    }

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
            isTopCardZoomed = false
            zoomToggleRequest = 0
            playRequest = 0
            retryRequest = 0
            motion.isDragging = false
            // The album picker resolved (or the user chose "Keep Without
            // Album"): the parked card leaves `visibleCards` with no fling of
            // its own, so give it a departing slot or it vanishes mid-deck.
            // Guarded on `visibleCards` rather than the top card, so a cancelled
            // picker (the card is still on screen) flings nothing.
            if let parked = albumCardPending,
               !viewModel.visibleCards.contains(where: { $0.id == parked.id }) {
                albumCardPending = nil
                flingOut(parked)
            }
            // Undo can land while the departing card is still flinging. That
            // card is back on top, and `slots` now renders it from `motion`
            // instead of its departing `flying` offset. Animating `motion.offset`
            // home (even though it is already zero) lets SwiftUI interpolate
            // from the on-screen fling position instead of teleporting the card
            // to deck center.
            if let returningId = viewModel.currentAsset?.id,
               departing.contains(where: { $0.id == returningId }) {
                withAnimation(.reduceMotionAware(
                    .spring(response: 0.35, dampingFraction: 0.8),
                    reduceMotion: reduceMotion
                )) {
                    motion.offset = .zero
                }
            } else if motion.offset != .zero {
                motion.offset = .zero
            }
        }
        .onChange(of: isTopCardZoomed) {
            // Zoom engaged mid-swipe-drag: the in-flight drag tears down
            // without onEnded, so snap the card back instead of leaving it
            // tilted with no swipe committed.
            if isTopCardZoomed {
                motion.isDragging = false
                snapBack()
            }
        }
    }

    // MARK: - Card Stack

    private var cardStack: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(slots) { slot in
                    let isTop = slot.depth == 0
                    let depth = CGFloat(slot.depth ?? 0)
                    let asset = slot.asset

                    CardView(
                        asset: asset,
                        photoService: viewModel.photoService,
                        isTopCard: isTop,
                        motion: slot.motion,
                        zoomToggleRequest: isTop ? zoomToggleRequest : 0,
                        playRequest: isTop ? playRequest : 0,
                        retryRequest: isTop ? retryRequest : 0,
                        onZoomChanged: isTop ? { isTopCardZoomed = $0 } : nil,
                        onSwipeDragChanged: handleDragChanged,
                        onSwipeDragEnded: handleDragEnded,
                        onImageShown: { shownAssetIds.insert($0) }
                    )
                    // Scoped so the stack shift animates on every path (swipe,
                    // skip, undo, album confirm) without touching the drag.
                    .animation(.reduceMotionAware(.smooth(duration: 0.3), reduceMotion: reduceMotion)) {
                        $0.scaleEffect(1.0 - depth * 0.05)
                            .offset(y: depth * 10)
                    }
                    .transition(.stateTransition)
                    // No `.gesture` here on purpose. A drag attached above
                    // CardView is starved: the card's own pinch holds the touch
                    // and the deck never sees `onChanged`. The swipe is relayed
                    // from CardView's gesture graph instead.
                    .allowsHitTesting(isTop && !viewModel.isPerformingMutation)
                    .accessibilityElement(children: .ignore)
                    .accessibilityHidden(!isTop)
                    .accessibilityLabel(isTop ? accessibilityLabel(for: asset) : Text(""))
                    .accessibilityActions {
                        if isTop {
                            Button("Delete") { commit(.delete) }
                            Button("Keep") { commit(.keep) }
                            Button("Add to Album") { commit(.album) }
                            Button("Skip") { commit(.skip) }
                            if !shownAssetIds.contains(asset.id) {
                                Button("Try Loading Again") { retryRequest += 1 }
                            }
                            if asset.mediaType == .video {
                                Button("Play Video") { playRequest += 1 }
                            } else {
                                Button(isTopCardZoomed ? "Zoom Out" : "Zoom In") {
                                    zoomToggleRequest += 1
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { deckSize = $0 }
        }
    }

    // MARK: - Swipe Drag (relayed from CardView)

    /// Relay for the top card's drag. The gesture itself lives on `CardView`
    /// (see `unifiedDrag`), because a drag attached anywhere above it is starved
    /// of every `onChanged` by the card's own pinch.
    private func handleDragChanged(_ assetId: String, _ translation: CGSize) {
        // The card under the finger must still be the top card: an undo (or a
        // skip) mid-drag re-points the deck at a different asset, and applying
        // this gesture to it would move the wrong photo.
        guard !viewModel.isPerformingMutation,
              assetId == viewModel.currentAsset?.id else { return }
        if !motion.isDragging {
            motion.isDragging = true
            HapticHelper.impact(.light)
        }
        motion.offset = translation
    }

    /// Relay for the top card's drag end. A pinch can zoom the card mid-drag
    /// (the drag was already in flight when the touch began) — snap back
    /// instead of committing a swipe the user replaced with an inspection.
    private func handleDragEnded(_ assetId: String, _ value: DragGesture.Value, cardWidth: CGFloat) {
        // An undo mid-drag puts a different card on top. Committing this gesture
        // would apply the in-flight swipe to the previous card, so drop it.
        guard !viewModel.isPerformingMutation,
              assetId == viewModel.currentAsset?.id else {
            motion.isDragging = false
            return
        }
        guard !isTopCardZoomed,
              let direction = SwipeDirection.resolve(
                translation: value.translation,
                predicted: value.predictedEndTranslation,
                cardWidth: cardWidth
              ) else {
            motion.isDragging = false
            snapBack()
            return
        }
        commit(direction, velocity: value.velocity)
    }

    /// Flings a card out of the deck without applying a decision. Used for the
    /// album card once the picker's choice has already advanced the view model,
    /// so its exit animates like every other decision instead of vanishing.
    private func flingOut(_ asset: AssetSummary) {
        let target = SwipeDirection.album.flingOffset(from: .zero, distance: flingDistance)
        let flying = CardMotion(offset: target)
        withAnimation(.reduceMotionAware(
            Animation.interpolatingSpring(duration: 0.35, bounce: 0, initialVelocity: 0),
            reduceMotion: reduceMotion
        ), completionCriteria: .logicallyComplete) {
            departing.removeAll { $0.id == asset.id }
            departing.append(DeckSlot(asset: asset, depth: nil, motion: flying))
        } completion: {
            departing.removeAll { $0.motion === flying }
        }
    }

    // MARK: - Commit

    /// The one path for every swipe, button, arrow key and VoiceOver action.
    private func commit(_ direction: SwipeDirection, velocity: CGSize = .zero) {
        guard viewModel.hasMoreCards, !viewModel.isPerformingMutation,
              let asset = viewModel.currentAsset else { return }
        motion.isDragging = false
        // Any fresh decision supersedes a card parked for the album picker (the
        // picker was dismissed without a choice), so it is not flung twice.
        albumCardPending = nil

        if direction == .delete, !canDeleteTopCard {
            // The photo never showed: refuse the delete and snap back.
            HapticHelper.notification(.warning)
            onDeleteBlocked()
            snapBack()
            return
        }
        HapticHelper.impact(direction == .skip ? .light : .heavy)

        if direction == .album {
            // Filing is an explicit choice: the card stays on top until the
            // picker resolves, and leaves (or stays) with the view model.
            snapBack()
            albumCardPending = asset
            viewModel.keepWithAlbum()
            return
        }

        let start = motion.offset
        let target = direction.flingOffset(from: start, distance: flingDistance)
        let flying = CardMotion(offset: target)
        let fling = Animation.interpolatingSpring(
            duration: 0.35,
            bounce: 0,
            initialVelocity: SwipeDirection.relativeVelocity(velocity, from: start, to: target)
        )
        withAnimation(.reduceMotionAware(fling, reduceMotion: reduceMotion), completionCriteria: .logicallyComplete) {
            departing.removeAll { $0.id == asset.id }
            departing.append(DeckSlot(asset: asset, depth: nil, motion: flying))
            motion.offset = .zero
            switch direction {
            case .delete: viewModel.swipeLeft()
            case .keep: viewModel.swipeRight()
            case .skip: viewModel.skip()
            case .album: break
            }
        } completion: {
            departing.removeAll { $0.motion === flying }
        }
        if direction == .delete { onUndoHint(asset.id) }
    }

    private func snapBack() {
        withAnimation(.reduceMotionAware(.spring(response: 0.4, dampingFraction: 0.7), reduceMotion: reduceMotion)) {
            motion.offset = .zero
        }
    }

    // MARK: - Accessibility

    private func accessibilityLabel(for asset: AssetSummary) -> Text {
        var parts: [String] = [asset.mediaType == .video ? "Video" : "Photo"]
        if let date = asset.creationDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        parts.append(asset.displaySize)
        if asset.isFavorite { parts.append("Favorite") }
        if asset.isLivePhoto { parts.append("Live Photo.") }
        if !asset.isLocallyAvailable { parts.append("In iCloud.") }
        if !shownAssetIds.contains(asset.id) { parts.append("Not loaded yet. Delete is off until it shows.") }
        return Text(parts.joined(separator: ", "))
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
        .disabled(!viewModel.hasMoreCards || viewModel.isPerformingMutation)
    }

    private func actionBarRow(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            // Delete button
            Button {
                commit(.delete)
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .scaledSquare(ScaledSize.actionButton)
                    .background(.red)
                    .clipShape(Circle())
            }
            // Keys follow the swipe: left deletes, right keeps.
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(!canDeleteTopCard)
            .opacity(canDeleteTopCard ? 1 : 0.4)
            .accessibilityLabel("Delete")
            .accessibilityHint("Marks this photo for deletion and shows the next one")

            // Skip button
            Button {
                commit(.skip)
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .scaledSquare(ScaledSize.secondaryActionButton)
                    .background(Color(.systemGray))
                    .clipShape(Circle())
            }
            .keyboardShortcut(.downArrow, modifiers: [])
            .accessibilityLabel("Skip")
            .accessibilityHint("Leaves this photo unchanged and shows the next one")

            // Add to Album button — same as an up-swipe
            Button {
                commit(.album)
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
                commit(.keep)
            } label: {
                Image(systemName: "checkmark")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .scaledSquare(ScaledSize.actionButton)
                    .background(.green)
                    .clipShape(Circle())
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .accessibilityLabel("Keep")
            .accessibilityHint("Keeps this photo without prompting")
        }
    }
}
