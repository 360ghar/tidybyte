import SwiftUI
import Charts
import UIKit

struct StorageDashboardView: View {
    @State private var viewModel = StorageDashboardViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(AppNavigation.self) private var appNavigation
    @Environment(LibraryChangeMonitor.self) private var libraryMonitor

    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                dashboardSkeleton
            } else {
                VStack(spacing: Spacing.xl) {
                    storageBreakdownSection
                        .fadeSlideIn(delay: 0.0)
                    deviceStorageSection
                        .fadeSlideIn(delay: 0.1)
                    appsAndOtherStorageSection
                        .fadeSlideIn(delay: 0.15)
                    iCloudSection
                        .fadeSlideIn(delay: 0.2)
                    trendSection
                        .fadeSlideIn(delay: 0.25)
                    cleanupOpportunitiesSection
                        .fadeSlideIn(delay: 0.3)
                }
                .padding(Spacing.lg)
                .readableWidth()
            }
        }
        .navigationTitle("Storage")
        .pullToRefresh {
            await viewModel.refresh(modelContext: modelContext)
        }
        .task(id: libraryMonitor.generation) {
            await viewModel.sync(to: libraryMonitor.generation, modelContext: modelContext)
        }
    }

    // MARK: - Skeleton

    private var dashboardSkeleton: some View {
        VStack(spacing: Spacing.xl) {
            storageBreakdownSkeleton
                .fadeSlideIn(delay: 0.0)
            deviceStorageSkeleton
                .fadeSlideIn(delay: 0.1)
            appsAndOtherStorageSkeleton
                .fadeSlideIn(delay: 0.15)
            iCloudSkeleton
                .fadeSlideIn(delay: 0.2)
            trendSkeleton
                .fadeSlideIn(delay: 0.25)
            cleanupOpportunitiesSkeleton
                .fadeSlideIn(delay: 0.3)
        }
        .padding(Spacing.lg)
        .readableWidth()
    }

    private var storageBreakdownSkeleton: some View {
        GlassCard {
            VStack(spacing: Spacing.lg) {
                SkeletonBar(width: 160, height: 16)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .center, spacing: Spacing.lg) {
                    ZStack {
                        SkeletonCircle(size: 180)
                        VStack(spacing: Spacing.xs) {
                            SkeletonBar(width: 70, height: 16)
                            SkeletonBar(width: 40, height: 10)
                        }
                    }
                    .frame(width: 180, height: 180)

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(0..<5, id: \.self) { _ in
                            HStack(spacing: Spacing.sm) {
                                SkeletonCircle(size: 10)
                                SkeletonBar(height: 12)
                                Spacer()
                                SkeletonBar(width: 50, height: 12)
                            }
                        }
                    }
                }
            }
        }
    }

    private var deviceStorageSkeleton: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                SkeletonBar(width: 130, height: 16)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SkeletonBar(height: 16)

                HStack {
                    SkeletonBar(width: 80, height: 10)
                    Spacer()
                    SkeletonBar(width: 90, height: 10)
                }
            }
        }
    }

    private var appsAndOtherStorageSkeleton: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                SkeletonBar(width: 160, height: 16)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SkeletonBar(height: 16)

                VStack(spacing: Spacing.sm) {
                    ForEach(0..<2, id: \.self) { _ in
                        HStack(spacing: Spacing.sm) {
                            SkeletonCircle(size: 10)
                            SkeletonBar(height: 12)
                            Spacer()
                            SkeletonBar(width: 50, height: 12)
                        }
                    }
                }

                SkeletonActionRow()
            }
        }
    }

    private var iCloudSkeleton: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    SkeletonCircle(size: 24)
                    SkeletonBar(width: 120, height: 16)
                    Spacer()
                }

                HStack {
                    SkeletonStatBlock(alignment: .leading)

                    Spacer()

                    Rectangle()
                        .fill(Color.cardBorder)
                        .frame(width: 1, height: 50)

                    Spacer()

                    SkeletonStatBlock(alignment: .trailing)
                }
            }
        }
    }

    private var trendSkeleton: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                SkeletonBar(width: 180, height: 16)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SkeletonBar(height: 150, cornerRadius: CornerRadius.small)

                HStack(spacing: Spacing.xs) {
                    SkeletonBar(width: 14, height: 14, cornerRadius: 2)
                    SkeletonBar(width: 160, height: 10)
                }
            }
        }
    }

    private var cleanupOpportunitiesSkeleton: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                SkeletonBar(width: 170, height: 16)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        SkeletonActionRow()
                        if index < 2 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Donut Chart

    private var storageBreakdownSection: some View {
        GlassCard {
            VStack(spacing: Spacing.lg) {
                Text("Library Breakdown")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if viewModel.categories.isEmpty {
                    EmptyStateView(icon: "photo.on.rectangle", title: "No Media", message: "Your library is empty.", iconColor: .blue)
                        .frame(height: 200)
                } else {
                    ZStack {
                        Chart(viewModel.categories) { category in
                            SectorMark(
                                angle: .value("Size", category.bytes),
                                innerRadius: .ratio(0.6),
                                angularInset: 2
                            )
                            .foregroundStyle(category.color)
                            .cornerRadius(4)
                        }
                        .frame(height: 200)

                        // Center label
                        VStack(spacing: Spacing.xs) {
                            Text(viewModel.totalLibrarySize.formattedFileSize)
                                .font(.title3.bold())
                            Text("\(viewModel.totalItemCount) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Legend
                    VStack(spacing: Spacing.sm) {
                        ForEach(viewModel.categories) { category in
                            HStack {
                                Circle()
                                    .fill(category.color)
                                    .frame(width: 10, height: 10)
                                Text(category.name)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(category.count)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(category.bytes.formattedFileSize)
                                    .font(.subheadline.monospacedDigit().bold())
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Device Storage

    private var deviceStorageSection: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                Text("Device Storage")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                GeometryReader { geometry in
                    let usedRatio = viewModel.deviceStorage.totalCapacity > 0
                        ? CGFloat(viewModel.deviceStorage.usedCapacity) / CGFloat(viewModel.deviceStorage.totalCapacity)
                        : 0

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: CornerRadius.small)
                            .fill(Color.cardSurface)
                        RoundedRectangle(cornerRadius: CornerRadius.small)
                            .fill(
                                usedRatio > 0.9
                                    ? LinearGradient(colors: [.red, .red.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                                    : LinearGradient.storageBarGradient
                            )
                            .frame(width: geometry.size.width * usedRatio)
                    }
                }
                .frame(height: 16)

                HStack {
                    Text("\(viewModel.deviceStorage.usedCapacity.formattedFileSize) used")
                        .font(.caption)
                    Spacer()
                    Text("\(viewModel.deviceStorage.availableCapacity.formattedFileSize) available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Apps, System & Other

    private var appsAndOtherStorageSection: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                Text("What Else Uses Storage")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                let total = viewModel.deviceStorage.totalCapacity
                // Hide the bar + legend when capacity couldn't be read or the estimate is empty,
                // so the card never renders misleading zeros — it still offers the Settings shortcut.
                if total > 0 && viewModel.appsAndOtherSize > 0 {
                    // Segmented bar splitting device capacity into media | apps-system-other | free.
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        let mediaWidth = width * ratio(viewModel.onDeviceMediaSize, of: total)
                        let otherWidth = width * ratio(viewModel.appsAndOtherSize, of: total)

                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: CornerRadius.small)
                                .fill(LinearGradient.storageBarGradient)
                                .frame(width: max(0, mediaWidth))
                            RoundedRectangle(cornerRadius: CornerRadius.small)
                                .fill(Color.otherCategory)
                                .frame(width: max(0, otherWidth))
                            // Flexible trailing segment fills the remainder = free space.
                            RoundedRectangle(cornerRadius: CornerRadius.small)
                                .fill(Color.cardSurface)
                        }
                    }
                    .frame(height: 16)

                    VStack(spacing: Spacing.sm) {
                        legendRow(style: LinearGradient.storageBarGradient, title: "Photos & Videos", note: "measured", bytes: viewModel.onDeviceMediaSize)
                        legendRow(style: Color.otherCategory, title: "Apps, system & other", note: "estimated", bytes: viewModel.appsAndOtherSize)
                    }
                }

                Text("TidyByte can't itemize individual apps — iOS keeps that private. Manage it in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // There is no public URL to deep-link the iPhone Storage screen.
                // `App-Prefs:root=General&path=STORAGE_MGMT` is a private/undocumented scheme that
                // risks App Store rejection, so it is deliberately NOT used. `openSettingsURLString`
                // (public) opens Settings at TidyByte's own page; the subtitle directs the user the
                // rest of the way. Do not "fix" this with the private scheme.
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    opportunityRow(
                        icon: "gearshape",
                        color: .gray,
                        title: "Manage Apps & System Storage",
                        detail: "Open Settings ▸ General ▸ iPhone Storage"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func ratio(_ part: Int64, of total: Int64) -> CGFloat {
        total > 0 ? min(1, CGFloat(part) / CGFloat(total)) : 0
    }

    private func legendRow<S: ShapeStyle>(style: S, title: String, note: String, bytes: Int64) -> some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(style)
                .frame(width: 10, height: 10)
            Text(title)
                .font(.subheadline)
            Text(note)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(bytes.formattedFileSize)
                .font(.subheadline.monospacedDigit().bold())
        }
    }

    // MARK: - iCloud

    private var iCloudSection: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                HStack {
                    Image(systemName: "icloud")
                        .font(.title3)
                        .foregroundStyle(.blue)
                    Text("iCloud Status")
                        .font(.headline)
                    Spacer()
                }

                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Local")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.localCount)")
                            .font(.title3.bold())
                        Text("items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Rectangle()
                        .fill(Color.cardBorder)
                        .frame(width: 1, height: 50)

                    Spacer()

                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text("iCloud Only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.iCloudOnlyCount)")
                            .font(.title3.bold())
                        Text(viewModel.iCloudOnlySize.formattedFileSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Trend

    private var trendSection: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                Text("Storage Trend (30 Days)")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if viewModel.snapshots.count < 2 {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("Not enough data yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                } else {
                    Chart(viewModel.snapshots) { snapshot in
                        LineMark(
                            x: .value("Date", snapshot.capturedAt),
                            y: .value("Size", snapshot.totalBytes)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Date", snapshot.capturedAt),
                            y: .value("Size", snapshot.totalBytes)
                        )
                        .foregroundStyle(.blue.opacity(0.1))
                    }
                    .frame(height: 150)
                    .chartYAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let bytes = value.as(Int64.self) {
                                    Text(bytes.formattedFileSize)
                                        .font(.caption2)
                                }
                            }
                        }
                    }

                    if let first = viewModel.snapshots.first,
                       let last = viewModel.snapshots.last {
                        let delta = last.totalBytes - first.totalBytes
                        HStack {
                            Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .foregroundStyle(delta >= 0 ? .orange : .green)
                            Text(delta >= 0
                                 ? "Added \(delta.formattedFileSize) in 30 days"
                                 : "Freed \(abs(delta).formattedFileSize) in 30 days")
                                .font(.caption)
                                .foregroundStyle(delta >= 0 ? .orange : .green)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cleanup Opportunities

    private var cleanupOpportunitiesSection: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                Text("Cleanup Opportunities")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(viewModel.opportunities) { opportunity in
                    Button {
                        appNavigation.showCleanup(tool: opportunity.tool)
                    } label: {
                        opportunityRow(icon: opportunity.icon, color: opportunity.color, title: opportunity.title, detail: opportunity.detail)
                    }
                    .buttonStyle(.plain)
                }

                // Recently Deleted isn't readable via PhotoKit (Apple hides the trash
                // album from third-party apps), so surface a static shortcut into the
                // Photos app instead of a data-backed count.
                Button {
                    if let url = URL(string: "photos-redirect://") { openURL(url) }
                } label: {
                    opportunityRow(
                        icon: "trash",
                        color: .gray,
                        title: "Recently Deleted",
                        detail: "Permanently remove deleted items in Photos to reclaim space"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func opportunityRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, Spacing.xs)
    }
}
