import SwiftUI

struct LivePhotosConverterView: View {
    @State private var viewModel = LivePhotosConverterViewModel()
    @State private var showConvertAllConfirm = false
    @State private var previewItem: LivePhotoItem?
    private let photoService = PhotoLibraryService()

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.items.isEmpty {
                EmptyStateView(
                    icon: "livephoto",
                    title: "No Live Photos",
                    message: "You don't have any Live Photos in your library.",
                    iconColor: .yellow
                )
            } else {
                contentView
            }
        }
        .navigationTitle("Live Photos")
        .alert("Convert All Live Photos", isPresented: $showConvertAllConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Convert All", role: .destructive) {
                Task {
                    await viewModel.convertAll()
                    HapticHelper.notification(.success)
                }
            }
        } message: {
            Text("This will convert all Live Photos to still images. The video component will be removed. This action cannot be undone.")
        }
        .alert("Conversion Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .fullScreenCover(item: $previewItem) { item in
            LivePhotoPreviewView(viewModel: viewModel, startItemId: item.id)
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        List {
            ForEach(0..<6, id: \.self) { _ in
                SkeletonRow()
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
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
                    Text("~\(viewModel.estimatedSavings.formattedFileSize) savings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.convertingAll {
                    ProgressView()
                        .padding(.trailing, Spacing.sm)
                    Text("Converting...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
                Text("Total: \(viewModel.totalSize.formattedFileSize) · Estimated savings: ~\(viewModel.estimatedSavings.formattedFileSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if viewModel.convertedCount > 0 || viewModel.deletedCount > 0 {
                    HStack(spacing: Spacing.sm) {
                        if viewModel.convertedCount > 0 {
                            Text("Converted \(viewModel.convertedCount) · Saved \(viewModel.totalSavedBytes.formattedFileSize)")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        if viewModel.deletedCount > 0 {
                            Text("Deleted \(viewModel.deletedCount)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "livephoto")
                .font(.title2)
                .foregroundStyle(.yellow.opacity(0.8))
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
                Task { await viewModel.convertSingle(itemId: item.id) }
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
            .disabled(viewModel.convertingAll)

        case .converting:
            ProgressView()

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
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }
}
