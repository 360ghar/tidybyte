import SwiftUI
import SwiftData

struct LivePhotosConverterView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = LivePhotosConverterViewModel()
    @State private var showConvertAllConfirm = false
    @State private var previewItem: LivePhotoItem?
    /// Set when a single Convert waits for the first-time explainer.
    @State private var explainerItemId: String?
    @AppStorage(LivePhotoConvertExplainer.storageKey) private var hasSeenExplainer = false
    @State private var isCelebrating = false
    @State private var celebrationStatLine: String?
    private let photoService = PhotoLibraryService.shared

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.items.isEmpty {
                EmptyStateView(
                    icon: "livephoto",
                    title: "No Live Photos",
                    message: "You don't have any Live Photos in your library.",
                    iconColor: CleanupTool.livePhotos.color,
                    // D12: refresh affordance — new Live Photos may have landed
                    // since the last fetch (parity with Large Files/Bursts).
                    actionTitle: "Refresh"
                ) {
                    Task { await viewModel.refresh() }
                }
            } else {
                contentView
            }
        }
        .navigationTitle("Live Photos")
        .toolbar {
            // Conversions are logged in the same history as compression.
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CompressionHistoryView()
                } label: {
                    Label("Conversion History", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .happyPathCelebration(isPresented: $isCelebrating, statLine: celebrationStatLine)
        .onDisappear {
            // D2: leaving the screen must stop Convert All — the loop deletes
            // originals and previously had no stop at all.
            viewModel.cancelConvertAll()
        }
        .alert("Convert All Live Photos", isPresented: $showConvertAllConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Convert All") {
                // D2: VM-owned task so cancellation works; haptic on full success.
                viewModel.startConvertAll(modelContext: modelContext)
            }
        } message: {
            Text(LivePhotoConvertExplainer.message)
        }
        .alert("Convert Live Photo", isPresented: .init(
            get: { explainerItemId != nil },
            set: { if !$0 { explainerItemId = nil } }
        )) {
            Button("Cancel", role: .cancel) { explainerItemId = nil }
            Button("Convert") {
                hasSeenExplainer = true
                if let id = explainerItemId {
                    explainerItemId = nil
                    Task { await viewModel.convertSingle(itemId: id, modelContext: modelContext) }
                }
            }
        } message: {
            Text(LivePhotoConvertExplainer.message)
        }
        .originalsKeptAlert(
            // No settable state backs this condition — keptOriginals is
            // VM-owned and the preview gate is local — so a constant binding.
            isPresented: .constant(!viewModel.keptOriginals.isEmpty && previewItem == nil),
            onTryAgain: { viewModel.retryRemovingOriginals() },
            onRemoveCopies: { viewModel.removeCopies() }
        )
        .onChange(of: viewModel.convertingAll) { was, isNow in
            // Happy path: celebrate only a fully-successful Convert All (the
            // COMP-09 pattern) — a user-cancelled batch is not a milestone.
            guard was, !isNow, !viewModel.isCancelled,
                  viewModel.errorMessage == nil,
                  let batch = viewModel.lastBatch,
                  batch.failed == 0, batch.converted > 0,
                  // Kept originals leave the "Originals Kept" alert open: not
                  // a clean success, and the rating sheet would collide with it.
                  viewModel.keptOriginals.isEmpty else { return }
            HappyPathReporter.fire(
                isCelebrating: $isCelebrating,
                statLine: $celebrationStatLine,
                line: "converted \(batch.converted) Live Photos"
            )
        }
        // Non-modal error surface. Also covers the batch summary
        // ("Converted 8 of 10. 2 failed."), which is a report rather than a
        // failure, so no retry is offered.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = viewModel.errorMessage {
                ToolErrorBanner(
                    message: message,
                    title: "Live Photos",
                    onDismiss: { viewModel.errorMessage = nil }
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
            }
        }
        .fullScreenCover(item: $previewItem) { item in
            LivePhotoPreviewView(viewModel: viewModel, startItemId: item.id)
        }
        .task {
            await viewModel.loadIfNeeded()
            // D1 (review pass): resolve any conversions a crash interrupted.
            await CompressionJournal.reconcile(modelContext: modelContext)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        ToolLoadingView { ToolSkeletonList() }
    }

    // MARK: - Content View

    private var contentView: some View {
        VStack(spacing: 0) {
            // Summary header
            summaryHeader
                .fadeSlideIn()

            List {
                ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                    livePhotoRow(item)
                        .fadeSlideIn(delay: Double(index) * 0.03)
                }
            }
            .listStyle(.plain)
            .pullToRefresh { await viewModel.refresh() }

            // Bottom action bar
            ActionBarView {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("\(viewModel.items.count) Live Photos")
                        .font(.caption.bold())
                    Text("est. ~\(viewModel.estimatedSavings.formattedFileSize) savings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.convertingAll || viewModel.phase != .idle {
                    ProgressView()
                        .padding(.trailing, Spacing.sm)
                    Text(ReplaceOriginalsNotice.phaseText(viewModel.phase))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    // D2: a real stop control. Step 2 is one iOS alert, so
                    // there is nothing left to stop then.
                    if viewModel.convertingAll, case .savingCopies = viewModel.phase {
                        Button("Stop", role: .destructive) {
                            HapticHelper.impact(.light)
                            viewModel.cancelConvertAll()
                        }
                        .font(.subheadline.bold())
                    }
                } else {
                    Button {
                        HapticHelper.impact(.light)
                        showConvertAllConfirm = true
                    } label: {
                        Text("Convert All")
                            .font(.headline)
                            .padding(.horizontal, Spacing.xxl)
                            .padding(.vertical, Spacing.sm)
                            .background(.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    }
                    .scaleOnPress()
                    .disabled(viewModel.isBusy)
                }
            }
        }
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("\(viewModel.items.count) Live Photos")
                    .font(.headline)
                Text("Total: \(viewModel.totalSize.formattedFileSize) · est. savings ~\(viewModel.estimatedSavings.formattedFileSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if viewModel.deletedCount > 0 {
                    Text("Deleted \(viewModel.deletedCount)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            Image(systemName: "livephoto")
                .font(.title2)
                .foregroundStyle(CleanupTool.livePhotos.color)
        }
        .glassCard()
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Live Photo Row

    private func livePhotoRow(_ item: LivePhotoItem) -> some View {
        HStack(spacing: Spacing.md) {
            Button {
                HapticHelper.impact(.light)
                previewItem = item
            } label: {
                HStack(spacing: Spacing.md) {
                    AsyncThumbnailView(assetId: item.id, photoService: photoService)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                        .overlay(
                            BadgeView(text: "LIVE", icon: "livephoto", color: .yellow)
                                .scaleEffect(0.8),
                            alignment: .topLeading
                        )

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        if let date = item.asset.creationDate {
                            Text(date, style: .date)
                                .font(.subheadline)
                        }

                        // Current size. Actual savings depend on the photo and are shown
                        // after conversion rather than guessed up front.
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "livephoto")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(item.asset.fileSize.formattedFileSize)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Live Photo preview")
            .accessibilityHint("Opens full-screen preview with motion playback")

            conversionButton(for: item)
        }
    }

    // MARK: - Conversion Button

    @ViewBuilder
    private func conversionButton(for item: LivePhotoItem) -> some View {
        switch item.conversionState {
        case .idle:
            Button {
                HapticHelper.impact(.light)
                if hasSeenExplainer {
                    Task { await viewModel.convertSingle(itemId: item.id, modelContext: modelContext) }
                } else {
                    explainerItemId = item.id
                }
            } label: {
                Text("Convert")
                    .font(.caption.bold())
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.cardSurface)
                    .foregroundStyle(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.small)
                            .strokeBorder(Color.cardBorder, lineWidth: 1)
                    )
            }
            .scaleOnPress()
            .disabled(viewModel.convertingAll || viewModel.isBusy)

        case .converting:
            ProgressView()

        case .copySaved:
            Label("Copy saved", systemImage: "checkmark")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .completed:
            HStack(spacing: Spacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if item.savedBytes > 0 {
                    Text("-\(item.savedBytes.formattedFileSize)")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

        case .failed(let error):
            VStack(spacing: Spacing.xs) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Color.destructive)
                    .lineLimit(3)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// First-time explainer for Live Photo conversion. Shared by the list and the
/// full-screen preview, which both offer a single Convert.
enum LivePhotoConvertExplainer {
    static let storageKey = "hasSeenLivePhotoConvertExplainer"
    static let message = ReplaceOriginalsNotice.explainer(
        copies: "the still image of each Live Photo as a new photo",
        originals: "the Live Photos"
    )
}
