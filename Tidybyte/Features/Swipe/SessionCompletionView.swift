import SwiftUI
import StoreKit

struct SessionCompletionView: View {
    @Bindable var viewModel: SwipeSessionViewModel
    @Environment(AppNavigation.self) private var appNavigation
    @Environment(\.requestReview) private var requestReview

    @State private var showCheckmark = false
    /// Where the user wanted to go when they hit an exit button while deletions
    /// were still pending — resolved after the confirmation dialog (SWIPE-02).
    @State private var pendingExit: ExitDestination?
    /// Success is recorded exactly once per session, either on appear (no
    /// batch deletions pending) or after the commit lands — never both.
    @State private var recordedSessionSuccess = false

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
    }

    private var completionContent: some View {
        VStack(spacing: Spacing.xxxl) {
            // Animated checkmark with glow
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.green.opacity(0.2), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .scaledSquare(ScaledSize.celebrationHalo)
                    .scaleEffect(showCheckmark ? 1.0 : 0.3)

                Image(systemName: "checkmark.circle.fill")
                    .scaledGlyph(ScaledSize.celebrationGlyph)
                    .foregroundStyle(.green)
                    .scaleEffect(showCheckmark ? 1.0 : 0.5)
                    .opacity(showCheckmark ? 1.0 : 0.0)
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showCheckmark)

            Text("Session Complete!")
                .font(.largeTitle.bold())
                .fadeSlideIn(delay: 0.2)

            // Stats card
            VStack(spacing: Spacing.lg) {
                deletionStatRow
                    .fadeSlideIn(delay: 0.3)
                statRow(icon: "checkmark", color: .green, label: "Kept", value: "\(stats.keptCount) items")
                    .fadeSlideIn(delay: 0.33)
                statRow(icon: "folder", color: .blue, label: "Organized", value: "\(stats.organizedCount) items")
                    .fadeSlideIn(delay: 0.35)
                statRow(icon: "forward.fill", color: .gray, label: "Skipped", value: "\(stats.skippedCount) items")
                    .fadeSlideIn(delay: 0.4)

                Rectangle()
                    .fill(Color.cardBorder)
                    .frame(height: 1)

                storageStatRow
                    .fadeSlideIn(delay: 0.45)
            }
            .glassCard()
            .padding(.horizontal, Spacing.lg)

            // Rate / Share always offered on the big happy path — this screen
            // is the best moment in the app, so the card is a permanent part
            // of it, not a transient banner.
            HappyPathPromptCard(statLine: celebrationStatLine)
                .padding(.horizontal, Spacing.lg)
                .fadeSlideIn(delay: 0.55)

            // Batch deletion confirmation
            if viewModel.hasPendingDeletions {
                VStack(spacing: Spacing.md) {
                    Button {
                        Task { await viewModel.commitDeletions() }
                    } label: {
                        HStack {
                            if viewModel.isDeletingBatch {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "trash.fill")
                            }
                            Text("Confirm Delete \(viewModel.pendingDeletionIds.count) Items")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.lg)
                        .background(.red.gradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                    }
                    .disabled(viewModel.isDeletingBatch)
                    .scaleOnPress()

                    Button {
                        viewModel.discardPendingDeletions()
                    } label: {
                        Text("Skip Deletion")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .disabled(viewModel.isDeletingBatch)
                }
                .padding(.horizontal, Spacing.lg)
                .fadeSlideIn(delay: 0.5)
            }

            // Action buttons
            VStack(spacing: Spacing.md) {
                Button {
                    requestExit(.swipeHome)
                } label: {
                    Text("Back to Swipe Home")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.lg)
                        .background(.blue.gradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                }
                .scaleOnPress()

                Button {
                    requestExit(.cleanupTools)
                } label: {
                    Text("Go to Cleanup Tools")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.lg)
                        .background(Color.cardSurface)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                        .overlay {
                            RoundedRectangle(cornerRadius: CornerRadius.large)
                                .strokeBorder(Color.cardBorder, lineWidth: 1)
                        }
                }
                .scaleOnPress()
            }
            .disabled(viewModel.isDeletingBatch)
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.lg)
            .fadeSlideIn(delay: viewModel.hasPendingDeletions ? 0.6 : 0.5)
        }
        .onAppear {
            showCheckmark = true
            HapticHelper.notification(.success)
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
            "You have \(viewModel.pendingDeletionIds.count) uncommitted deletions.",
            isPresented: Binding(
                get: { pendingExit != nil },
                set: { if !$0 { pendingExit = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Commit Deletion", role: .destructive) {
                if let destination = pendingExit {
                    commitAndExit(to: destination)
                }
            }
            Button("Discard") {
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
            Text("Delete them, keep them, or discard?")
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
        if AppPreferences.recordSuccessfulAction() {
            requestReview()
            AppPreferences.recordReviewPromptDate()
        }
    }

    private var celebrationStatLine: String? {
        if viewModel.deletionCommitted, stats.deletedCount > 0 {
            return "cleared \(stats.deletedCount) photos and freed \(stats.deletedBytes.formattedFileSize)"
        }
        let reviewed = stats.keptCount + stats.organizedCount + stats.skippedCount
        return reviewed > 0 ? "reviewed \(reviewed) photos" : nil
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

    // MARK: - Stat Rows

    @ViewBuilder
    private var deletionStatRow: some View {
        if viewModel.deletionCommitted {
            statRow(icon: "trash", color: .red, label: "Deleted", value: "\(stats.deletedCount) items")
        } else if !viewModel.pendingDeletionIds.isEmpty {
            statRow(icon: "trash", color: .orange, label: "Marked for Deletion", value: "\(viewModel.pendingDeletionIds.count) items")
        } else {
            statRow(icon: "trash", color: .red, label: "Deleted", value: "0 items")
        }
    }

    @ViewBuilder
    private var storageStatRow: some View {
        if viewModel.deletionCommitted {
            statRow(icon: "internaldrive", color: .green, label: "Storage Freed",
                    value: stats.deletedBytes.formattedFileSize)
        } else if !viewModel.pendingDeletionIds.isEmpty {
            statRow(icon: "internaldrive", color: .orange, label: "Potential Savings",
                    value: stats.deletedBytes.formattedFileSize)
        } else {
            statRow(icon: "internaldrive", color: .green, label: "Storage Freed",
                    value: stats.deletedBytes.formattedFileSize)
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
