import SwiftUI

struct SessionCompletionView: View {
    @Bindable var viewModel: SwipeSessionViewModel
    @Environment(AppNavigation.self) private var appNavigation

    @State private var showCheckmark = false

    private var stats: SessionStats { viewModel.sessionStats }
    private var hasPendingDeletions: Bool {
        !viewModel.pendingDeletionIds.isEmpty && !viewModel.deletionCommitted
    }

    var body: some View {
        VStack(spacing: Spacing.xxxl) {
            Spacer()

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
                    .frame(width: 140, height: 140)
                    .scaleEffect(showCheckmark ? 1.0 : 0.3)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
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

            // Batch deletion confirmation
            if hasPendingDeletions {
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

            Spacer()

            // Action buttons
            VStack(spacing: Spacing.md) {
                Button {
                    appNavigation.returnToSwipeHome()
                } label: {
                    Text("Start Another Session")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.lg)
                        .background(.blue.gradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                }
                .scaleOnPress()

                Button {
                    appNavigation.showCleanupHome()
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
            .fadeSlideIn(delay: hasPendingDeletions ? 0.6 : 0.5)
        }
        .navigationBarBackButtonHidden()
        .onAppear {
            showCheckmark = true
            HapticHelper.notification(.success)
        }
        .alert("Deletion Error", isPresented: .init(
            get: { viewModel.deletionErrorMessage != nil },
            set: { if !$0 { viewModel.deletionErrorMessage = nil } }
        )) {
            Button("Retry") {
                viewModel.deletionErrorMessage = nil
                Task { await viewModel.commitDeletions() }
            }
            Button("OK", role: .cancel) { viewModel.deletionErrorMessage = nil }
        } message: {
            Text(viewModel.deletionErrorMessage ?? "")
        }
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
