import SwiftUI
import Photos

struct SwipeSessionView: View {
    @Bindable var viewModel: SwipeSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AppNavigation.self) private var appNavigation

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var swipeTask: Task<Void, Never>?
    /// Single transient-message channel. The undo hint and the one-time zoom
    /// hint both surface here so they can never stack or overlap.
    @State private var toast: ToastMessage?
    /// True while the top card is pinch-zoomed: the swipe drag yields so a
    /// one-finger drag pans the photo instead of committing a swipe.
    @State private var isTopCardZoomed = false
    /// Monotonic counter driving CardView's "Zoom" accessibility action.
    @State private var zoomToggleRequest = 0
    @AppStorage(AppPreferences.Key.hasSeenZoomHint) private var hasSeenZoomHint = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isBootstrapping = !viewModel.hasLoadedInitialAssets || viewModel.isLoading

        VStack(spacing: 0) {
            // Progress bar
            progressBar

            if isBootstrapping {
                Spacer()
                ProgressView("Loading photos...")
                Spacer()
            } else if viewModel.visibleCards.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
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
        }
        .toast($toast)
        .navigationTitle("Swipe Session")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if viewModel.hasPendingDeletions {
                        // Route through the end-session review so pending deletions
                        // aren't silently dropped (they were never committed).
                        Task { await viewModel.endSession() }
                    } else {
                        // Nothing marked for deletion — behave like a normal back,
                        // but release the prefetch cache first (SWIPE-01).
                        Task { await viewModel.stopAllCaching() }
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .accessibilityLabel("Back")
                .accessibilityHint("Returns to the swipe home; reviews pending deletions first if any")
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await viewModel.endSession() }
                } label: {
                    Text("End")
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("End session")
                .accessibilityHint("Ends the session and reviews your changes")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.undo() }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                // Undo is inert during the animation window (wrong-card
                // attribution, B1) and mid-commit (would resurrect a card the
                // batch is deleting right now, B2).
                .disabled(viewModel.undoStack.isEmpty || viewModel.isSwiping || viewModel.isDeletingBatch)
                .accessibilityLabel("Undo")
                .accessibilityHint("Reverts your last swipe")
            }
        }
        .sheet(isPresented: $viewModel.showAlbumPicker, onDismiss: {
            viewModel.cancelPendingKeep()
        }) {
            AlbumPickerSheet(
                photoService: viewModel.photoService,
                onAlbumSelected: { albumId in
                    await viewModel.addToAlbum(albumId: albumId)
                },
                onSkip: {
                    viewModel.skipKeep()
                }
            )
            .presentationDetents([.medium, .large])
        }
        .navigationDestination(isPresented: $viewModel.showCompletion) {
            SessionCompletionView(viewModel: viewModel)
        }
        // Non-modal error surface. The session is a full-screen task flow — a
        // modal here blocks swiping until dismissed, while the banner leaves
        // the deck usable when the failure is non-fatal.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = viewModel.errorMessage {
                ToolErrorBanner(
                    message: message,
                    title: "Swipe Session",
                    onDismiss: { viewModel.errorMessage = nil }
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
            }
        }
        .task {
            await viewModel.loadAssetsIfNeeded()
            // One-time zoom hint, only when there is actually a card to pinch.
            // An empty deck leaves the flag unset so the hint fires on a
            // later session that has cards.
            if !hasSeenZoomHint, viewModel.hasMoreCards {
                hasSeenZoomHint = true
                flashZoomHint()
            }
            // Register the live session so external launches (deep link /
            // widget / intent) can respect the pending-deletion review gate
            // instead of tearing the session down blindly (A1). Deliberately
            // never cleared here: the reference is weak, a new session
            // overwrites it, and any session that reaches home has already
            // resolved its deletions through the review gate — so a stale
            // entry can never wrongly trigger the gate. Registering only here
            // (not pairing with onDisappear) matters: onDisappear fires when
            // the completion screen pushes on top, which is exactly when the
            // gate must stay armed.
            appNavigation.setActiveSwipeSession(viewModel)
        }
        .onChange(of: viewModel.deletionReviewRequested) { _, requested in
            // A deep link asked for a new session while this one held uncommitted
            // deletions — push the review instead of tearing down silently (A1).
            guard requested else { return }
            viewModel.clearDeletionReviewRequest()
            Task { await viewModel.endSession() }
        }
        .onChange(of: appNavigation.swipeDismissRequestID) { _, _ in
            // External dismissal (deep link / tab switch): never drop pending
            // deletions silently — route through the completion review first
            // (APP-07).
            if viewModel.hasPendingDeletions {
                Task { await viewModel.endSession() }
            } else {
                Task { await viewModel.stopAllCaching() }
                dismiss()
            }
        }
        .onChange(of: viewModel.currentIndex) {
            // The deck advanced (swipe/skip/undo/album confirm) — the parent
            // owns the zoom flag, so clear it here rather than trusting the
            // outgoing card's callback (whose onZoomChanged prop is already
            // nil by teardown time). Resetting the request counter also stops
            // a promoted card from re-firing a stale VoiceOver zoom request.
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
                dragOffset = .zero
                isDragging = false
            }
        }
        .onDisappear {
            swipeTask?.cancel()
            // Any path that leaves the session view (back, empty-state exit,
            // external dismissal, completion push) releases the prefetch cache
            // so a session never pins images in the image manager (SWIPE-01).
            Task { await viewModel.stopAllCaching() }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            let progress = viewModel.assets.isEmpty ? 0 : CGFloat(viewModel.currentIndex) / CGFloat(viewModel.assets.count)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(.systemGray5))
                Rectangle()
                    .fill(.blue)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 3)
        .accessibilityElement()
        .accessibilityLabel("Review progress")
        .accessibilityValue("\(min(viewModel.currentIndex, viewModel.assets.count)) of \(viewModel.assets.count) reviewed")
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
                        zoomToggleRequest: isTop ? zoomToggleRequest : 0,
                        onZoomChanged: isTop ? { isTopCardZoomed = $0 } : nil
                    )
                    .scaleEffect(isTop ? 1.0 : scale)
                    .offset(y: isTop ? 0 : yOffset)
                    .offset(x: isTop ? dragOffset.width : 0, y: isTop ? dragOffset.height : 0)
                    .rotationEffect(isTop ? .degrees(Double(dragOffset.width / 20)) : .zero)
                    .gesture(
                        isTop && !isTopCardZoomed && !viewModel.isPerformingMutation && !viewModel.isSwiping
                            ? dragGesture(cardWidth: geometry.size.width)
                            : nil
                    )
                    .animation(.reduceMotionAware(.spring(response: 0.3, dampingFraction: 0.8), reduceMotion: reduceMotion), value: dragOffset)
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

    // MARK: - Drag Gesture

    private func dragGesture(cardWidth: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    HapticHelper.impact(.light)
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                isDragging = false
                // A pinch can zoom the card mid-drag (the drag gesture was
                // already attached when the touch began) — snap back instead
                // of committing a swipe the user replaced with an inspection.
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
                        flashUndoHint()
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
            flashUndoHint()
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

    private func flashUndoHint() {
        toast = ToastMessage(text: "Marked for deletion — tap Undo to restore", systemImage: "trash")
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            if viewModel.allPhotosAlreadySwiped {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("All Photos Reviewed!")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                Text("You've already swiped through all your photos. Try \"All Media\" to review again, or reset swipe history in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, Spacing.xxl)

                Button {
                    dismiss()
                } label: {
                    Text("Try Another Filter")
                        .font(.headline)
                        .padding(.horizontal, Spacing.xxxl)
                        .padding(.vertical, Spacing.md)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                }
                .scaleOnPress()
            } else if !viewModel.isPhotoLibraryAccessible {
                // A permission problem reads as an empty library; surface it
                // instead of "All Caught Up!" (SWIPE-09).
                Image(systemName: "lock.shield")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)

                Text("Photo Access Required")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("TidyByte needs photo library access to show your photos here. Grant access in Settings, then try again.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, Spacing.xxl)

                Button {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.headline)
                        .padding(.horizontal, Spacing.xxxl)
                        .padding(.vertical, Spacing.md)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                }
                .scaleOnPress()
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("All Caught Up!")
                    .font(.title2.bold())
                Text("No more photos to review with this filter.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // A failed/empty fetch reads the same as a genuinely empty deck —
                // offer a retry so a transient failure isn't a dead end (SWIPE-09).
                Button {
                    Task {
                        viewModel.retryLoad()
                        await viewModel.loadAssetsIfNeeded()
                    }
                } label: {
                    Text("Try Again")
                        .font(.headline)
                        .padding(.horizontal, Spacing.xxxl)
                        .padding(.vertical, Spacing.md)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                }
                .scaleOnPress()
            }
        }
        .padding()
    }

    private func flashZoomHint() {
        toast = ToastMessage(text: "Pinch or double-tap a photo to inspect it", systemImage: "magnifyingglass")
    }

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
                if !isDragging {
                    dragOffset = .zero
                }
            }
            await action()
            viewModel.endSwipeAnimation()
        }
    }
}
