import SwiftUI

struct SwipeSessionView: View {
    @Bindable var viewModel: SwipeSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryChangeMonitor.self) private var libraryMonitor
    @Environment(AppNavigation.self) private var appNavigation
    /// The app-wide handler `RootView` injects, so the empty-state permission
    /// block offers the same ask the tab gate does.
    @Environment(PhotoPermissionHandler.self) private var permissionHandler
    /// The progress bar is the one animation on this screen that ignored
    /// Reduce Motion; read it here so the bar matches the deck and completion
    /// animations.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Single transient-message channel. The undo hint and the one-time zoom
    /// hint both surface here so they can never stack or overlap.
    @State private var toast: ToastMessage?
    /// Drives the shared pre-prompt explainer when the empty state has to ask
    /// for access rather than hand the user off to Settings.
    @State private var showPermissionPrimer = false
    @AppStorage(AppPreferences.Key.hasSeenZoomHint) private var hasSeenZoomHint = false
    /// The explanatory undo text shows the first few times only; after that
    /// the toast is just "Marked for deletion" with its Undo button.
    @AppStorage("swipeUndoHintCount") private var undoHintCount = 0

    var body: some View {
        let isBootstrapping = !viewModel.hasLoadedInitialAssets || viewModel.isLoading

        VStack(spacing: 0) {
            // Progress bar
            progressBar
            if viewModel.filter == .worstShots, viewModel.skippedAnalysisCount > 0 {
                Text(L10n.format("%lld photo could not be scored from a local image.",
                                 fallback: "%lld photos could not be scored from a local image.",
                                 viewModel.skippedAnalysisCount))
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, Spacing.lg)
            }

            if isBootstrapping {
                Spacer()
                if viewModel.filter == .worstShots {
                    ProgressView("Scoring photos", value: viewModel.analysisProgress)
                        .padding(.horizontal, Spacing.xxl)
                    Button("Cancel") { viewModel.cancelLoading(); dismiss() }
                        .frame(minHeight: 44)
                } else {
                    ProgressView("Loading photos...")
                }
                Spacer()
            } else if viewModel.visibleCards.isEmpty, !viewModel.showCompletion {
                // While the completion screen pushes, the deck stays mounted
                // so the last card's fling plays out instead of vanishing.
                // Scrolls at large text sizes; centered when it fits.
                GeometryReader { proxy in
                    ScrollView {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: proxy.size.height)
                    }
                }
            } else {
                // The card stack and its action bar live in their own view so a
                // drag frame re-renders only the deck, not this whole screen.
                SwipeCardDeck(viewModel: viewModel, onUndoHint: { markedId in
                    // A ToastMessage carries a plain String, so these have to be
                    // looked up here — `Text` never sees them.
                    let text = undoHintCount < 3
                        ? L10n.string("Marked for deletion. Nothing is deleted until you confirm at the end.")
                        : L10n.string("Marked for deletion")
                    undoHintCount += 1
                    toast = ToastMessage(text: text, systemImage: "trash", actionTitle: L10n.string("Undo")) {
                        // Verify before clearing: a stale tap must not silently
                        // dismiss the hint while the photo stays pending-delete.
                        // The pending check comes first because `undoStack` is
                        // not authoritative — a committed or discarded batch
                        // leaves its `.deleted` entries behind, and undoing one
                        // does nothing.
                        guard viewModel.isPendingDeletion(markedId),
                              viewModel.undoStack.contains(where: { $0.asset.id == markedId && $0.decision == .deleted }) else {
                            toast = ToastMessage(text: L10n.string("That photo can't be undone anymore."), style: .warning)
                            return
                        }
                        guard let last = viewModel.undoStack.last,
                              last.decision == .deleted, last.asset.id == markedId else {
                            toast = ToastMessage(text: L10n.string("Undo your newer actions first to reach that photo."), style: .warning)
                            return
                        }
                        toast = nil
                        Task { await viewModel.undo() }
                    }
                }, onDeleteBlocked: {
                    toast = ToastMessage(text: L10n.string("Delete is off until the photo loads."), systemImage: "hourglass", style: .warning)
                })
            }
        }
        .task(id: ReviewReasonTaskID(asset: viewModel.currentAsset, generation: libraryMonitor.generation, completion: viewModel.showCompletion)) {
            await viewModel.refreshReviewReason()
        }
        .onChange(of: permissionHandler.permissionState) { _, newState in
            // Returning from Settings with access fixed is exactly the step the
            // recovery card asks for, so re-read here instead of making the user
            // also find Try Again. Only an access-empty deck reloads; a deck that
            // is merely finished keeps its completion state.
            guard viewModel.emptyReason != nil,
                  newState == .authorized || newState == .limited else { return }
            Task { await reloadEmptyDeck() }
        }
        .onChange(of: libraryMonitor.generation) { _, _ in
            // Widening a limited selection (or any library change) bumps the
            // generation. An access-empty deck re-reads so the photos the user
            // just shared show up without a second manual step.
            guard viewModel.emptyReason != nil else { return }
            Task { await reloadEmptyDeck() }
        }
        // Kept alongside the observer above: that one is debounced and depends on
        // change details arriving, while this fires deterministically when the
        // system limited-library picker is dismissed.
        .onReceive(NotificationCenter.default.publisher(for: .photoLibrarySelectionDidChange)) { _ in
            guard viewModel.emptyReason != nil else { return }
            Task { await reloadEmptyDeck() }
        }
        .toast($toast)
        .photoPermissionPrimer(isPresented: $showPermissionPrimer, permissionHandler: permissionHandler)
        .localizedNavigationTitle("Swipe Session")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // The count sits under the title, clear of the toast area.
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("Swipe Session")
                        .font(.headline)
                    if !viewModel.assets.isEmpty {
                        Text("\(min(viewModel.currentIndex + 1, viewModel.assets.count)) of \(viewModel.assets.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
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
                    // Neutral: ending reviews changes, it deletes nothing.
                    Text("End")
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
                .keyboardShortcut("z", modifiers: .command)
                // Undo is inert mid-commit (would resurrect a card the batch is
                // deleting right now, B2).
                .disabled(viewModel.undoStack.isEmpty || viewModel.isDeletingBatch)
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
                    // View-model text: already localized where it is built, so the
                    // lookup misses and falls back to the text itself.
                    message: LocalizedStringKey(message),
                    onDismiss: { viewModel.errorMessage = nil }
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
            }
        }
        .task {
            // Capture the hosting tab before an asynchronous scan can outlive a tab switch.
            // Keep the weak reference through the completion push so external launches
            // still respect pending deletions. A new session replaces it.
            appNavigation.setActiveSwipeSession(viewModel)
            await viewModel.loadAssetsIfNeeded()
            // One-time zoom hint, only when there is actually a card to pinch.
            // An empty deck leaves the flag unset so the hint fires on a
            // later session that has cards.
            if !hasSeenZoomHint, viewModel.hasMoreCards {
                hasSeenZoomHint = true
                flashZoomHint()
            }
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
        .onChange(of: viewModel.hasPendingDeletions) { _, _ in
            // Committed or discarded: a navigation request parked behind those
            // ids can now be applied without destroying anything.
            appNavigation.applyDeferredLinkIfPossible()
        }
        .onDisappear {
            viewModel.cancelLoading()
            // Any path that leaves the session view (back, empty-state exit,
            // external dismissal, completion push) releases the prefetch cache
            // so a session never pins images in the image manager (SWIPE-01).
            Task { await viewModel.stopAllCaching() }
            appNavigation.applyDeferredLinkIfPossible()
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
        .animation(.reduceMotionAware(.smooth, reduceMotion: reduceMotion), value: viewModel.currentIndex)
        .accessibilityElement()
        .accessibilityLabel("Review progress")
        .accessibilityValue("\(min(viewModel.currentIndex, viewModel.assets.count)) of \(viewModel.assets.count) reviewed")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            if viewModel.allPhotosAlreadySwiped {
                Image(systemName: "checkmark.seal")
                    .scaledGlyph(ScaledSize.stateGlyph)
                    .foregroundStyle(.green)

                Text("All Photos Reviewed!")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                Text("You've already swiped through all your photos. Try \"All Media\" to review again, or reset swipe history in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
                // instead of "All Caught Up!" (SWIPE-09). Copy and the offered
                // action come from the shared presentation model, so this screen
                // can never disagree with the tab gate about what a state means —
                // in particular `.restricted` offers no button, because Screen
                // Time or device management keeps the Photos switch disabled.
                let presentation = permissionHandler.permissionState.presentation

                Image(systemName: "lock.shield")
                    .scaledGlyph(ScaledSize.stateGlyph)
                    .foregroundStyle(.orange)

                // Keyed rather than resolved: the copy comes from `L10n`, and a
                // resolved `String` would render verbatim without reading the
                // `\.locale` a language switch changes. See `RootView`.
                Text(LocalizedStringKey(presentation.title))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(presentation.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)

                switch presentation.action {
                case .requestPermission:
                    Button {
                        showPermissionPrimer = true
                    } label: {
                        emptyStateButtonLabel("Allow Access")
                    }
                    .scaleOnPress()
                case .openSettings:
                    Button {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    } label: {
                        emptyStateButtonLabel("Open Settings")
                    }
                    .scaleOnPress()
                case .none:
                    EmptyView()
                }
            } else if let reason = viewModel.emptyReason {
                // Access is granted but there is nothing to read: limited access
                // with no photos shared, or a device-side permission problem
                // under full access. Both used to land on "All Caught Up!" and
                // read as a broken app (SWIPE-09). The card states the cause and
                // the steps out of it.
                PhotoRecoveryCard(presentation: reason.recovery) { action in
                    switch action {
                    case .retry:
                        Task { await reloadEmptyDeck() }
                    case .addPhotos, .openSettings:
                        PhotoRecoveryPresentation.Action.perform(action)
                    }
                }
            } else {
                Image(systemName: "checkmark.circle")
                    .scaledGlyph(ScaledSize.stateGlyph)
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
                    Task { await reloadEmptyDeck() }
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

    /// Re-reads a deck that came back empty for an access reason.
    ///
    /// Shared by the card's "Try Again" button and the two automatic triggers
    /// below, so returning from Settings or widening a limited selection reloads
    /// the deck without the user having to hunt for the button the copy just
    /// told them about.
    private func reloadEmptyDeck() async {
        // Two triggers fire on the same frame when access is fixed (the
        // permission change and the library generation), and `retryLoad()`
        // clears `isLoading`, so without this guard each one started a full
        // load and the second overwrote the first mid-read.
        guard !viewModel.isLoading else { return }
        viewModel.retryLoad()
        await viewModel.loadAssetsIfNeeded()
    }

    /// Filled primary button for the empty state, matching the styling of the
    /// other empty-state actions.
    private func emptyStateButtonLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal, Spacing.xxxl)
            .padding(.vertical, Spacing.md)
            .background(.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    private func flashZoomHint() {
        toast = ToastMessage(text: L10n.string("Pinch or double-tap a photo to inspect it"), systemImage: "magnifyingglass")
    }
}

private struct ReviewReasonTaskID: Hashable {
    let asset: AssetSummary?
    let generation: Int
    let completion: Bool
}
