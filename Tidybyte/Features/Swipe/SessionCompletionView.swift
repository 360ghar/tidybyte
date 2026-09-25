import SwiftUI

struct SessionCompletionView: View {
    @Bindable var viewModel: SwipeSessionViewModel
    @Environment(AppNavigation.self) private var appNavigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showCheckmark = false
    /// Where the user wanted to go when they hit an exit button while deletions
    /// were still pending — resolved after the confirmation dialog (SWIPE-02).
    @State private var pendingExit: ExitDestination?
    /// Success is recorded exactly once per session, either on appear (no
    /// batch deletions pending) or after the commit lands — never both.
    @State private var recordedSessionSuccess = false
    @State private var isCelebrating = false

    private enum ExitDestination {
        case swipeHome
        case cleanupTools
    }

    private var stats: SessionStats { viewModel.sessionStats }

    var body: some View {
        // The stats + celebration stack can exceed small-device height: the
        // screen scrolls when it must and stays vertically centered when all
        // content fits.
        GeometryReader { proxy in
            ScrollView {
                completionContent
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
            }
        }
        .navigationBarBackButtonHidden()
        .happyPathCelebration(isPresented: $isCelebrating, statLine: celebrationStatLine)
    }

    /// The deck ran out with nothing left pending, or the deletions were
    /// committed. Only then is this a finished session worth celebrating.
    /// An early exit, or keeping everything mid-deck, is not.
    private var isFinished: Bool {
        !viewModel.hasPendingDeletions && (viewModel.deletionCommitted || !viewModel.hasMoreCards)
    }

    private var title: String {
        if viewModel.hasPendingDeletions { return "Review Changes" }
        return viewModel.hasMoreCards ? "Session Ended" : "Session Complete"
    }

    private var pendingCount: Int { viewModel.pendingDeletionIds.count }

    static func items(_ count: Int) -> String {
        "\(count) item\(count == 1 ? "" : "s")"
    }

    private var completionContent: some View {
        VStack(spacing: Spacing.xxl) {
            if isFinished {
                Image(systemName: "checkmark.circle.fill")
                    .scaledGlyph(ScaledSize.celebrationGlyph)
                    .foregroundStyle(Color.success)
                    .scaleEffect(showCheckmark ? 1.0 : 0.8)
                    .animation(.reduceMotionAware(.spring(response: 0.5, dampingFraction: 0.7), reduceMotion: reduceMotion), value: showCheckmark)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            // The one decision on this screen comes first, above the stats.
            if viewModel.hasPendingDeletions {
                pendingDeletionBlock
            }

            // Stats card
            VStack(spacing: Spacing.lg) {
                deletionStatRow
                statRow(icon: "checkmark", color: Color.success, label: "Kept", value: Self.items(stats.keptCount))
                statRow(icon: "folder", color: .blue, label: "Added to albums", value: Self.items(stats.organizedCount))
                statRow(icon: "forward.fill", color: .gray, label: "Skipped", value: Self.items(stats.skippedCount))
                if viewModel.deletionCommitted, stats.deletedBytes > 0 {
                    statRow(icon: "internaldrive", color: Color.success, label: "Moved to Recently Deleted",
                            value: stats.deletedBytes.formattedFileSize)
                }
            }
            .glassCard()
            .padding(.horizontal, Spacing.lg)

            RecentlyDeletedNotice()

            // One primary action; the second exit is a plain text button.
            VStack(spacing: Spacing.md) {
                Button {
                    requestExit(.swipeHome)
                } label: {
                    Text("Start Another Session")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.lg)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                }
                .scaleOnPress()

                Button("Go to Cleanup Tools") {
                    requestExit(.cleanupTools)
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
            }
            .disabled(viewModel.isDeletingBatch)
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.lg)
        }
        .readableWidth()
        .padding(.top, Spacing.xl)
        .onAppear {
            showCheckmark = true
            if isFinished {
                HapticHelper.notification(.success)
            }
            // Batch mode records later (after commit); immediate-commit mode
            // already has its final counts on appear.
            if !viewModel.hasPendingDeletions {
                recordSessionSuccess()
            }
        }
        .onChange(of: viewModel.deletionCommitted) { _, committed in
            if committed {
                recordSessionSuccess()
            }
        }
        .confirmationDialog(
            "\(pendingCount) item\(pendingCount == 1 ? " is" : "s are") marked for deletion",
            isPresented: Binding(
                get: { pendingExit != nil },
                set: { if !$0 { pendingExit = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete \(pendingCount) Item\(pendingCount == 1 ? "" : "s")", role: .destructive) {
                if let destination = pendingExit {
                    commitAndExit(to: destination)
                }
            }
            Button("Keep All Items") {
                if let destination = pendingExit {
                    discardAndExit(to: destination)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingExit = nil
                // Back to the live deck — Cancel must not strand the user on
                // the completion screen (B3).
                viewModel.showCompletion = false
            }
        } message: {
            Text("Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.")
        }
        // Non-modal error surface. Retry is preserved from the alert it
        // replaces: a failed commit leaves the pending set intact, so
        // re-running the commit is the correct recovery.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = viewModel.deletionErrorMessage {
                ToolErrorBanner(
                    message: message,
                    title: "Deletion Error",
                    onRetry: {
                        viewModel.deletionErrorMessage = nil
                        Task { await viewModel.commitDeletions() }
                    },
                    onDismiss: { viewModel.deletionErrorMessage = nil }
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
            }
        }
    }

    // MARK: - Happy-Path Review Gating

    /// Counts the session as one successful action only when the user actually
    /// did something (deleted, kept, or organized) — a session exited mid-deck
    /// with zero interactions is not a happy path.
    private func recordSessionSuccess() {
        guard !recordedSessionSuccess else { return }
        guard stats.deletedCount > 0 || stats.keptCount > 0 || stats.organizedCount > 0 else { return }
        recordedSessionSuccess = true
        // Ask only on a real finish, never after an early exit. The success
        // haptic already played on appear.
        if isFinished {
            // A previous early exit earned this milestone. `recordSuccess` would
            // count the action again and look for the NEXT milestone, so consume
            // the held one directly. Held in UserDefaults, so a recreated
            // completion view does not drop it. Consumed either way: someone who
            // rated the app since earning it must not be prompted again.
            if AppPreferences.hasPendingReviewMilestone() {
                if HappyPathReporter.consumePendingReviewMilestone(hasRated: AppPreferences.hasRatedApp()) {
                    isCelebrating = true
                }
            } else {
                HappyPathReporter.recordSuccess(presenting: $isCelebrating)
            }
        } else if AppPreferences.recordSuccessfulAction() {
            // The action counts either way, but the milestone it earned cannot
            // be presented mid-exit. Hold it for the next real finish.
            AppPreferences.savePendingReviewMilestone(true)
        }
    }

    private var celebrationStatLine: String? {
        if viewModel.deletionCommitted, stats.deletedCount > 0 {
            return "cleared \(Self.items(stats.deletedCount)) (\(stats.deletedBytes.formattedFileSize))"
        }
        let reviewed = stats.keptCount + stats.organizedCount + stats.skippedCount
        return reviewed > 0 ? "reviewed \(Self.items(reviewed))" : nil
    }

    // MARK: - Exit Flow (SWIPE-02)

    /// Every exit button routes through here so pending deletions are never
    /// dropped silently: with uncommitted deletions the user gets a
    /// commit/discard/cancel dialog first and stays on the review screen on
    /// cancel.
    private func requestExit(_ destination: ExitDestination) {
        guard viewModel.hasPendingDeletions else {
            performExit(to: destination)
            return
        }
        pendingExit = destination
    }

    private func performExit(to destination: ExitDestination) {
        switch destination {
        case .swipeHome:
            appNavigation.returnToSwipeHome()
        case .cleanupTools:
            appNavigation.showCleanupHome()
        }
    }

    private func commitAndExit(to destination: ExitDestination) {
        pendingExit = nil
        Task {
            await viewModel.commitDeletions()
            // Only leave once the deletion actually committed — on failure the
            // error alert keeps the user on the review screen with a Retry.
            guard viewModel.deletionCommitted else { return }
            performExit(to: destination)
        }
    }

    private func discardAndExit(to destination: ExitDestination) {
        pendingExit = nil
        viewModel.discardPendingDeletions()
        performExit(to: destination)
    }

    // MARK: - Pending Deletions

    private var pendingDeletionBlock: some View {
        VStack(spacing: Spacing.md) {
            Text("\(Self.items(pendingCount)) marked for deletion · \(viewModel.pendingDeletionBytes.formattedFileSize)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await viewModel.commitDeletions() }
            } label: {
                HStack {
                    if viewModel.isDeletingBatch {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Delete \(pendingCount) Item\(pendingCount == 1 ? "" : "s")")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.lg)
                .background(Color.destructive)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
            }
            .disabled(viewModel.isDeletingBatch)
            .scaleOnPress()

            Button("Keep All Items") {
                viewModel.discardPendingDeletions()
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .disabled(viewModel.isDeletingBatch)

            Text("Deleted items go to Recently Deleted in Photos for 30 days.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Spacing.lg)
    }

    // MARK: - Stat Rows

    @ViewBuilder
    private var deletionStatRow: some View {
        if viewModel.hasPendingDeletions {
            statRow(icon: "trash", color: .orange, label: "Marked for deletion", value: Self.items(pendingCount))
        } else {
            statRow(icon: "trash", color: Color.destructive, label: "Deleted", value: Self.items(stats.deletedCount))
        }
    }

    private func statRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)

            Text(label)
                .font(.body)

            Spacer()

            Text(value)
                .font(.body.bold())
                .foregroundStyle(.secondary)
        }
    }
}
