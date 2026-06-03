import SwiftUI

struct SwipeSessionView: View {
    @Bindable var viewModel: SwipeSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AppNavigation.self) private var appNavigation

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var swipeTask: Task<Void, Never>?
    @State private var showUndoHint = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let hapticLight = UIImpactFeedbackGenerator(style: .light)
    private let hapticHeavy = UIImpactFeedbackGenerator(style: .heavy)

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
        .overlay(alignment: .top) {
            if showUndoHint {
                undoHintBanner
            }
        }
        .navigationTitle("Swipe Session")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if viewModel.pendingDeletionIds.isEmpty {
                        // Nothing marked for deletion — behave like a normal back.
                        dismiss()
                    } else {
                        // Route through the end-session review so pending deletions
                        // aren't silently dropped (they were never committed).
                        Task { await viewModel.endSession() }
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
                .disabled(viewModel.undoStack.isEmpty)
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
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            await viewModel.loadAssetsIfNeeded()
        }
        .onChange(of: appNavigation.swipeDismissRequestID) { _, _ in
            dismiss()
        }
        .onDisappear {
            swipeTask?.cancel()
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
                        dragOffset: isTop ? dragOffset : .zero
                    )
                    .scaleEffect(isTop ? 1.0 : scale)
                    .offset(y: isTop ? 0 : yOffset)
                    .offset(x: isTop ? dragOffset.width : 0, y: isTop ? dragOffset.height : 0)
                    .rotationEffect(isTop ? .degrees(Double(dragOffset.width / 20)) : .zero)
                    .gesture(isTop && !viewModel.isPerformingMutation ? dragGesture(cardWidth: geometry.size.width) : nil)
                    .animation(.reduceMotionAware(.spring(response: 0.3, dampingFraction: 0.8), reduceMotion: reduceMotion), value: dragOffset)
                    .allowsHitTesting(isTop && !viewModel.isPerformingMutation)
                    .accessibilityElement(children: .ignore)
                    .accessibilityHidden(!isTop)
                    .accessibilityLabel(isTop ? accessibilityLabel(for: asset) : Text(""))
                    .accessibilityActions {
                        if isTop {
                            Button("Delete") { triggerDelete() }
                            Button("Keep") { triggerKeep() }
                            Button("Skip") { viewModel.skip() }
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
                    hapticLight.impactOccurred()
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                isDragging = false
                let threshold = cardWidth * 0.4
                let velocityThreshold: CGFloat = 500
                let predictedWidth = value.predictedEndTranslation.width

                if value.translation.width > threshold || predictedWidth > velocityThreshold {
                    // Swipe right — keep
                    hapticHeavy.impactOccurred()
                    performSwipeAnimation(offset: CGSize(width: 1000, height: value.translation.height)) {
                        viewModel.swipeRight()
                    }
                } else if value.translation.width < -threshold || predictedWidth < -velocityThreshold {
                    // Swipe left — delete
                    hapticHeavy.impactOccurred()
                    performSwipeAnimation(offset: CGSize(width: -1000, height: value.translation.height)) {
                        viewModel.swipeLeft()
                        flashUndoHint()
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
        parts.append(asset.formattedFileSize)
        if asset.isFavorite { parts.append("Favorite") }
        if asset.isLivePhoto { parts.append("Live Photo.") }
        if !asset.isLocallyAvailable { parts.append("In iCloud.") }
        return Text(parts.joined(separator: ", "))
    }

    private func triggerDelete() {
        guard viewModel.hasMoreCards, !viewModel.isPerformingMutation else { return }
        hapticHeavy.impactOccurred()
        performSwipeAnimation(offset: CGSize(width: -1000, height: 0)) {
            viewModel.swipeLeft()
            flashUndoHint()
        }
    }

    private func triggerKeep() {
        guard viewModel.hasMoreCards, !viewModel.isPerformingMutation else { return }
        hapticHeavy.impactOccurred()
        performSwipeAnimation(offset: CGSize(width: 1000, height: 0)) {
            viewModel.swipeRight()
        }
    }

    private func flashUndoHint() {
        withAnimation { showUndoHint = true }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { showUndoHint = false }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 32) {
            // Delete button
            Button {
                triggerDelete()
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(.red)
                    .clipShape(Circle())
                    .shadow(color: .red.opacity(0.3), radius: 8)
            }
            .accessibilityLabel("Delete")
            .accessibilityHint("Marks this photo for deletion and shows the next one")

            // Info / Skip button
            Button {
                viewModel.skip()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color(.systemGray))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Skip")
            .accessibilityHint("Leaves this photo unchanged and shows the next one")

            // Keep / Add to Album button
            Button {
                triggerKeep()
            } label: {
                Image(systemName: "checkmark")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(.green)
                    .clipShape(Circle())
                    .shadow(color: .green.opacity(0.3), radius: 8)
            }
            .accessibilityLabel("Keep")
            .accessibilityHint("Keeps this photo and lets you add it to an album")
        }
        .disabled(!viewModel.hasMoreCards || viewModel.isPerformingMutation)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: viewModel.allPhotosAlreadySwiped ? "checkmark.seal" : "checkmark.circle")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            if viewModel.allPhotosAlreadySwiped {
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
            } else {
                Text("All Caught Up!")
                    .font(.title2.bold())
                Text("No more photos to review with this filter.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    private var undoHintBanner: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "trash")
            Text("Marked for deletion — tap Undo to restore")
                .font(.footnote.weight(.medium))
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Capsule().fill(Color.black.opacity(0.8)))
        .padding(.top, Spacing.sm)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityHidden(true)
    }

    private func performSwipeAnimation(
        offset: CGSize,
        action: @escaping @MainActor () async -> Void
    ) {
        guard !viewModel.isPerformingMutation else { return }
        withAnimation(.reduceMotionAware(.spring(response: 0.3, dampingFraction: 0.8), reduceMotion: reduceMotion)) {
            dragOffset = offset
        }

        swipeTask?.cancel()
        swipeTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dragOffset = .zero
            }
            await action()
        }
    }
}
