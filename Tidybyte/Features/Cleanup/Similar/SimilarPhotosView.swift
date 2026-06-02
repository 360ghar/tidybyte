import SwiftUI

struct SimilarPhotosView: View {
    @State private var viewModel = SimilarPhotosViewModel()
    @State private var showDeleteConfirm = false
    @State private var selectedGroup: SimilarGroup?
    private let photoService = PhotoLibraryService()

    var body: some View {
        Group {
            switch viewModel.scanState {
            case .idle:
                idleView
                    .transition(.stateTransition)
            case .scanning(let progress):
                scanningView(progress: progress)
                    .transition(.stateTransition)
            case .completed:
                resultsView
                    .transition(.stateTransition)
            case .error(let message):
                errorView(message: message)
                    .transition(.stateTransition)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.scanState)
        .navigationTitle("Similar Photos")
        .toolbar {
            if viewModel.scanState == .completed && !viewModel.groups.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete All") {
                        HapticHelper.impact(.light)
                        showDeleteConfirm = true
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .navigationDestination(item: $selectedGroup) { group in
            SimilarGroupDetailView(
                group: group,
                selectedForDeletion: $viewModel.selectedForDeletion,
                onSetBest: { assetId, groupId in
                    viewModel.setBest(assetId: assetId, in: groupId)
                }
            )
        }
        .alert("Delete Similar Photos", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.selectedForDeletion.count) Items", role: .destructive) {
                Task {
                    await viewModel.deleteSelected()
                    HapticHelper.notification(.success)
                }
            }
        } message: {
            Text("The best photo from each group will be kept.")
        }
        .alert("Similar Photos Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Idle View

    private var idleView: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                Spacer(minLength: Spacing.xxxl)

                // Hero icon
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.blue.opacity(0.15), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)

                    Image(systemName: "square.on.square")
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(.blue.opacity(0.8))
                        .subtleShadow()
                }
                .fadeSlideIn()

                VStack(spacing: Spacing.sm) {
                    Text("Find Similar Photos")
                        .font(.title2.bold())

                    Text("Groups photos taken within \(Int(viewModel.timeWindow)) seconds of each other.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xxxl)
                }
                .fadeSlideIn(delay: 0.05)

                // Time window slider
                VStack(spacing: Spacing.sm) {
                    Text("Time Window: \(Int(viewModel.timeWindow))s")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Slider(value: $viewModel.timeWindow, in: 1...60, step: 1)
                        .padding(.horizontal, Spacing.xxxl)
                        .onChange(of: viewModel.timeWindow) {
                            HapticHelper.selection()
                        }
                }
                .glassCard()
                .padding(.horizontal, Spacing.lg)
                .fadeSlideIn(delay: 0.1)

                Button {
                    HapticHelper.impact(.light)
                    Task { await viewModel.scan() }
                } label: {
                    Text("Start Scan")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                }
                .scaleOnPress()
                .padding(.horizontal, Spacing.xxxl)
                .fadeSlideIn(delay: 0.15)

                Spacer(minLength: Spacing.xxxl)
            }
        }
    }

    // MARK: - Scanning View

    private func scanningView(progress: Float) -> some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.blue.opacity(0.15), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.blue.opacity(0.8))
                    .symbolEffect(.pulse)
            }

            VStack(spacing: Spacing.md) {
                Text("Grouping similar photos...")
                    .font(.headline)

                ProgressView(value: progress)
                    .tint(.blue)
                    .padding(.horizontal, Spacing.xxxl)

                Text("\(Int(progress * 100))%")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.blue)
                    .animatedNumber()
            }
            .glassCard()
            .padding(.horizontal, Spacing.lg)

            Spacer()
        }
        .fadeSlideIn()
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        EmptyStateView(
            icon: "exclamationmark.triangle",
            title: "Something Went Wrong",
            message: message,
            iconColor: .orange,
            actionTitle: "Retry"
        ) {
            HapticHelper.impact(.light)
            viewModel.scanState = .idle
        }
    }

    // MARK: - Results View

    private var resultsView: some View {
        Group {
            if viewModel.groups.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "No Similar Photos Found",
                    message: "Your library looks clean!",
                    iconColor: .green,
                    actionTitle: "Scan Again"
                ) {
                    HapticHelper.impact(.light)
                    viewModel.scanState = .idle
                }
            } else {
                VStack(spacing: 0) {
                    List {
                        // Summary card
                        Section {
                            HStack(spacing: Spacing.md) {
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text("\(viewModel.groups.count) groups found")
                                        .font(.headline)
                                    Text("\(viewModel.totalDuplicateCount) extras · \(viewModel.selectedSavingsBytes.formattedFileSize) selected")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "square.on.square")
                                    .font(.title2)
                                    .foregroundStyle(.blue.opacity(0.7))
                            }
                            .glassCard()
                            .listRowInsets(EdgeInsets(top: Spacing.sm, leading: Spacing.lg, bottom: Spacing.sm, trailing: Spacing.lg))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .fadeSlideIn()

                        // Groups
                        ForEach(Array(viewModel.groups.enumerated()), id: \.element.id) { index, group in
                            groupRow(group)
                                .fadeSlideIn(delay: Double(index) * 0.03)
                        }
                    }
                    .listStyle(.plain)
                    .pullToRefresh { await viewModel.scan() }

                    // Bottom action bar
                    if !viewModel.selectedForDeletion.isEmpty {
                        ActionBarView {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("\(viewModel.selectedForDeletion.count) selected")
                                    .font(.caption.bold())
                                Text(viewModel.selectedSavingsBytes.formattedFileSize)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                HapticHelper.impact(.light)
                                showDeleteConfirm = true
                            } label: {
                                Text("Delete Selected")
                                    .font(.headline)
                                    .padding(.horizontal, Spacing.xxl)
                                    .padding(.vertical, Spacing.sm)
                                    .background(Color.destructive)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                            }
                            .scaleOnPress()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Group Row

    private func groupRow(_ group: SimilarGroup) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("\(group.assets.count) photos")
                    .font(.subheadline.bold())
                Spacer()
                if let date = group.assets.first?.creationDate {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    selectedGroup = group
                } label: {
                    Label("Review", systemImage: "chevron.right")
                        .font(.caption.bold())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Review similar photo group")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(group.assets) { asset in
                        let quality = group.qualityScores[asset.id]
                        VStack(spacing: Spacing.xs) {
                            ZStack(alignment: .topTrailing) {
                                AsyncThumbnailView(assetId: asset.id, photoService: photoService)
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CornerRadius.small)
                                            .stroke(asset.id == group.bestAssetId ? Color.green : Color.clear, lineWidth: 2)
                                    )
                                    .overlay(alignment: .bottom) {
                                        if let quality {
                                            sharpnessBar(quality.sharpness)
                                                .padding(.horizontal, Spacing.xs)
                                                .padding(.bottom, Spacing.xs)
                                                .accessibilityLabel("Sharpness \(Int((quality.sharpness * 100).rounded())) percent")
                                        }
                                    }
                                    .overlay(alignment: .topLeading) {
                                        if let icon = exposureIcon(quality) {
                                            Image(systemName: icon)
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(3)
                                                .background(Color.black.opacity(0.5), in: Circle())
                                                .padding(Spacing.xs)
                                        }
                                    }

                                if asset.id == group.bestAssetId {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                        .padding(Spacing.xs)
                                } else {
                                    Button {
                                        HapticHelper.selection()
                                        viewModel.toggleSelection(asset.id)
                                    } label: {
                                        Image(systemName: viewModel.selectedForDeletion.contains(asset.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(viewModel.selectedForDeletion.contains(asset.id) ? .red : .white)
                                            .padding(Spacing.xs)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(viewModel.selectedForDeletion.contains(asset.id) ? "Keep photo" : "Select photo for deletion")
                                    .accessibilityAddTraits(viewModel.selectedForDeletion.contains(asset.id) ? [.isButton, .isSelected] : .isButton)
                                }
                            }

                            if asset.id == group.bestAssetId {
                                Label(group.bestReason.rawValue, systemImage: "star.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, Spacing.xs)
                                    .padding(.vertical, 2)
                                    .background(Color.success, in: Capsule())
                                    .accessibilityLabel("Recommended to keep: \(group.bestReason.rawValue)")
                            } else {
                                Button {
                                    HapticHelper.selection()
                                    viewModel.setBest(assetId: asset.id, in: group.id)
                                } label: {
                                    Text("Keep This")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Keep this photo as best")
                            }
                        }
                        .frame(width: 80)
                    }
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Quality chips

    private func sharpnessBar(_ value: Float) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.black.opacity(0.35))
            Capsule()
                .fill(sharpnessColor(value))
                .frame(width: max(3, 64 * CGFloat(min(1, max(0, value)))))
        }
        .frame(width: 64, height: 4)
    }

    private func sharpnessColor(_ value: Float) -> Color {
        if value >= 0.6 { return .success }
        if value >= 0.4 { return .warning }
        return .destructive
    }

    /// Returns an SF Symbol only when the photo is flagged dark/bright — nothing
    /// for well-exposed photos, so the common case stays uncluttered.
    private func exposureIcon(_ quality: AssetQuality?) -> String? {
        guard let quality else { return nil }
        if quality.isTooDark { return "moon.fill" }
        if quality.isOverexposed { return "sun.max.fill" }
        return nil
    }
}
