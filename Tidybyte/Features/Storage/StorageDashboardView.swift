import SwiftUI
import SwiftData
import Charts
import UIKit

enum BreakdownMode: String, CaseIterable {
    case byYear = "By Year"
    case bySource = "By Source"
}

struct StorageDashboardView: View {
    @State private var viewModel = StorageDashboardViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(AppNavigation.self) private var appNavigation
    @Environment(LibraryChangeMonitor.self) private var libraryMonitor

    @State private var breakdownMode: BreakdownMode = .byYear

    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                dashboardSkeleton
            } else {
                VStack(spacing: Spacing.xl) {
                    LimitedLibraryBanner(note: "Library figures below cover only the photos you selected; device totals cover the whole device.")

                    storageBreakdownSection
                        .fadeSlideIn(delay: 0.0)

                    if !viewModel.wins.isEmpty {
                        reclaimHeroSection
                            .fadeSlideIn(delay: 0.05)
                    }

                    deviceStorageSection
                        .fadeSlideIn(delay: 0.1)

                    appsAndOtherStorageSection
                        .fadeSlideIn(delay: 0.15)

                    recentlyDeletedSection
                        .fadeSlideIn(delay: 0.2)

                    cameraFormatSection

                    whereStorageGoesSection
                        .fadeSlideIn(delay: 0.25)

                    iCloudSection
                        .fadeSlideIn(delay: 0.3)

                    trendSection
                        .fadeSlideIn(delay: 0.35)

                    savingsSection
                        .fadeSlideIn(delay: 0.4)
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

    private var cameraFormatSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Camera Formats").font(.headline)
                ForEach(viewModel.cameraFormats) { format in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("\(format.id): \(format.count) items").font(.subheadline)
                        Text(MediaCleanerViewModel.sizeLabel(format.assets))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("These formats can overlap. Sizes describe your library, not space you will free.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("ProRAW, ProRes, and RAW+JPEG totals are unavailable from the Photos subtype metadata used here.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("For smaller future captures, open Settings → Camera → Formats and review High Efficiency, ProRAW, and ProRes where available. This does not change existing media.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Skeleton

    private var dashboardSkeleton: some View {
        VStack(spacing: Spacing.xl) {
            storageBreakdownSkeleton
                .fadeSlideIn(delay: 0.0)

            reclaimHeroSkeleton
                .fadeSlideIn(delay: 0.05)

            deviceStorageSkeleton
                .fadeSlideIn(delay: 0.1)

            appsAndOtherStorageSkeleton
                .fadeSlideIn(delay: 0.15)

            recentlyDeletedSkeleton
                .fadeSlideIn(delay: 0.2)

            whereStorageGoesSkeleton
                .fadeSlideIn(delay: 0.25)

            iCloudSkeleton
                .fadeSlideIn(delay: 0.3)

            trendSkeleton
                .fadeSlideIn(delay: 0.35)

            savingsSkeleton
                .fadeSlideIn(delay: 0.4)
        }
        .padding(Spacing.lg)
        .readableWidth()
    }

    private var savingsSkeleton: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                SkeletonBar(width: 140, height: 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SkeletonBar(height: 16)
            }
        }
    }

    /// Mirrors `recentlyDeletedSection`'s single-row card so the skeleton and the
    /// loaded body stay the same height when `wins` is non-empty.
    private var recentlyDeletedSkeleton: some View {
        GlassCard {
            HStack(spacing: Spacing.md) {
                SkeletonCircle(size: 28)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    SkeletonBar(width: 170, height: 12)
                    SkeletonBar(width: 180, height: 10)
                }

                Spacer()

                SkeletonBar(width: 10, height: 14, cornerRadius: 2)
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private var reclaimHeroSkeleton: some View {
        GlassCard {
            VStack(spacing: Spacing.lg) {
                SkeletonBar(width: 140, height: 20)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SkeletonBar(height: 16)

                VStack(spacing: Spacing.sm) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: Spacing.sm) {
                            SkeletonCircle(size: 10)
                            SkeletonBar(height: 12)
                            Spacer()
                        }
                    }
                }

                SkeletonBar(width: 100, height: 16)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var whereStorageGoesSkeleton: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                SkeletonBar(width: 140, height: 16)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SkeletonBar(width: 120, height: 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, Spacing.sm)

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

    // MARK: - Reclaimable Hero

    private var reclaimHeroSection: some View {
        GlassCard {
            VStack(spacing: Spacing.lg) {
                HStack {
                    Text("You Could Free")
                        .font(.headline)
                    Spacer()
                }

                VStack(spacing: Spacing.xs) {
                    Text("Up to \(viewModel.totalReclaimable.formattedFileSize)")
                        .font(.title3.bold())
                    Text("On this iPhone. Live Photos and large videos count at about half their size.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Segmented wins bar — each segment is tappable. Segment widths are
                // sized off a budget that subtracts inter-segment spacing, so the HStack
                // fills the GeometryReader width exactly instead of overflowing by
                // (n−1)×spacing and clipping the last segment.
                let total = viewModel.totalReclaimable
                let segmentSpacing: CGFloat = 2
                if total > 0 {
                    GeometryReader { geometry in
                        let gapBudget = segmentSpacing * CGFloat(max(0, viewModel.wins.count - 1))
                        let usable = max(0, geometry.size.width - gapBudget)
                        HStack(spacing: segmentSpacing) {
                            ForEach(viewModel.wins) { win in
                                Button {
                                    handle(win.action)
                                } label: {
                                    RoundedRectangle(cornerRadius: CornerRadius.small)
                                        .fill(win.color)
                                        .frame(maxWidth: usable * CGFloat(win.bytes) / CGFloat(total))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: 24)
                    // The legend rows below repeat every segment with a name.
                    .accessibilityHidden(true)
                }

                // Legend rows — each win is tappable.
                VStack(spacing: Spacing.sm) {
                    ForEach(viewModel.wins) { win in
                        Button {
                            handle(win.action)
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Circle()
                                    .fill(win.color)
                                    .frame(width: 10, height: 10)
                                Text(win.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(win.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Primary CTA — routes to the biggest win.
                if let firstWin = viewModel.wins.first {
                    Button {
                        handle(firstWin.action)
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "play.fill")
                            Text("Review now")
                                .font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(Color.cardSurface)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    }
                    .scaleOnPress()
                }
            }
        }
    }

    // MARK: - Your Savings

    /// Entry point into Activity & Savings. Always rendered (unlike the reclaim
    /// hero, which needs data-backed wins) so the feature is discoverable before
    /// the user has cleaned anything.
    private var savingsSection: some View {
        GlassCard {
            Button {
                HapticHelper.impact(.light)
                handle(.activity)
            } label: {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Your Savings")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        if viewModel.lifetimeItemCount > 0 {
                            // "Zero KB freed" would be misleading — the items
                            // really were cleaned, their sizes just weren't
                            // readable (iCloud-only assets report 0 bytes).
                            Text("\(savingsHeadline) · \(viewModel.lifetimeItemCount) items cleaned")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Track everything you clean up over time")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, Spacing.xs)
            }
            .buttonStyle(.plain)
        }
    }

    /// "X freed" when a size is known, otherwise an honest size-free label.
    private var savingsHeadline: String {
        viewModel.lifetimeFreedBytes > 0
            ? "\(viewModel.lifetimeFreedBytes.formattedFileSize) cleaned up"
            : "Sizes unavailable"
    }

    // MARK: - Recently Deleted

    /// Always-shown shortcut to empty the Photos trash. PhotoKit doesn't expose the
    /// "Recently Deleted" album (Apple hides it from third-party apps), so — unlike the
    /// reclaim wins — this can't be counted or sized; it's a static hand-off to Photos.
    /// Rendered outside `reclaimHeroSection` so it stays visible even when there are no
    /// data-backed reclaimable wins.
    private var recentlyDeletedSection: some View {
        GlassCard {
            Button {
                if let url = URL(string: "photos-redirect://") { openURL(url) }
            } label: {
                opportunityRow(
                    icon: "trash",
                    color: .gray,
                    title: "Recently Deleted",
                    detail: "Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted."
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Library Breakdown (Donut)

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
                            .cornerRadius(CornerRadius.small)
                        }
                        .frame(height: 200)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Library breakdown")
                        .accessibilityValue(viewModel.categories
                            .map { "\($0.name) \($0.bytes.formattedFileSize)" }
                            .joined(separator: ", "))

                        // Center label
                        VStack(spacing: Spacing.xs) {
                            Text(viewModel.totalLibrarySize.formattedFileSize)
                                .font(.title3.bold())
                            Text("\(viewModel.totalItemCount) \(viewModel.totalItemCount == 1 ? "item" : "items")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Tappable legend
                    VStack(spacing: Spacing.sm) {
                        ForEach(viewModel.categories) { category in
                            tappableLegendRow(category: category)
                        }
                    }
                }
            }
        }
    }

    /// The tool a legend row opens, if any.
    private static func action(for categoryId: String) -> StorageAction? {
        switch categoryId {
        case "screenshots": .cleanup(.screenshots)
        case "videos": .cleanup(.videoCompression)
        case "livePhotos": .cleanup(.livePhotos)
        default: nil  // Photos and Other have no direct cleanup tool
        }
    }

    /// Legend row that navigates to the appropriate tool when tapped.
    @ViewBuilder
    private func tappableLegendRow(category: StorageCategory) -> some View {
        if let action = Self.action(for: category.id) {
            Button {
                handle(action)
            } label: {
                legendRowContent(category: category, isTappable: true)
            }
            .buttonStyle(.plain)
        } else {
            legendRowContent(category: category, isTappable: false)
        }
    }

    /// Chevron only on rows that open a tool, so a row that does nothing on
    /// tap does not look like one that does.
    private func legendRowContent(category: StorageCategory, isTappable: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
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
            // The slot is kept only when some row is tappable, so values
            // still line up; with no tappable row there is no gap.
            if isTappable || viewModel.categories.contains(where: { Self.action(for: $0.id) != nil }) {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .opacity(isTappable ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 32)
    }

    // MARK: - Device Storage

    /// Hidden when capacity could not be read, so it never shows
    /// "Zero KB used / Zero KB available".
    @ViewBuilder
    private var deviceStorageSection: some View {
        if viewModel.deviceStorage.totalCapacity > 0 {
        let usedRatio = CGFloat(viewModel.deviceStorage.usedCapacity) / CGFloat(viewModel.deviceStorage.totalCapacity)
        let isAlmostFull = usedRatio > 0.9
        GlassCard {
            VStack(spacing: Spacing.md) {
                HStack {
                    Text("Device Storage")
                        .font(.headline)
                    Spacer()
                    // Text, not only a red bar, so the warning does not rely
                    // on color.
                    if isAlmostFull {
                        Label("Almost full", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(Color.destructive)
                    }
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: CornerRadius.small)
                            .fill(Color.cardSurface)
                        RoundedRectangle(cornerRadius: CornerRadius.small)
                            .fill(isAlmostFull ? Color.destructive : Color.accentColor)
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
                                .fill(Color.accentColor)
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
                        legendRow(style: Color.accentColor, title: "Photos & Videos", note: "estimated", bytes: viewModel.onDeviceMediaSize)
                        legendRow(style: Color.otherCategory, title: "Apps, system & other", note: "estimated", bytes: viewModel.appsAndOtherSize)
                    }

                    Text("Items in Recently Deleted still use space until Photos empties it, so \"Apps, system & other\" can grow right after a cleanup.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("TidyByte can't list single apps. iOS keeps that private. Manage it in Settings.")
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

    // MARK: - Where Your Storage Goes

    private var whereStorageGoesSection: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                Text("Where Your Storage Goes")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Picker("", selection: $breakdownMode) {
                    ForEach(BreakdownMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                let buckets = breakdownMode == .byYear ? viewModel.byYear : viewModel.bySource

                if buckets.isEmpty {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No data available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                            Button {
                                handle(.swipe(.customAssetIds(Set(bucket.assetIds))))
                            } label: {
                                breakdownRow(label: bucket.label, count: bucket.count, bytes: bucket.bytes)
                            }
                            .buttonStyle(.plain)

                            if index < buckets.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func breakdownRow(label: String, count: Int, bytes: Int64) -> some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(label)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text("\(count) \(count == 1 ? "item" : "items")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(bytes.formattedFileSize)
                .font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(.primary)

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, Spacing.xs)
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

    /// Days between the first and last snapshot, for honest wording: the
    /// chart can hold 2 snapshots taken 2 days apart.
    private var trendSpanLabel: String {
        guard let first = viewModel.snapshots.first?.capturedAt,
              let last = viewModel.snapshots.last?.capturedAt else { return "" }
        // Calendar days, not 24-hour spans: snapshots are taken once per day
        // at whatever time the app opens.
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: last)).day ?? 0
        return days < 1 ? "today" : "in \(days) day\(days == 1 ? "" : "s")"
    }

    /// Y range fitted to the data (with a margin), so a 1% change is visible
    /// instead of a flat line on a zero-based axis.
    private var trendDomain: ClosedRange<Int64> {
        let values = viewModel.snapshots.map(\.totalBytes)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let margin = max((high - low) / 5, 50_000_000)
        return max(0, low - margin)...(high + margin)
    }

    private var trendSection: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                Text("Library Size")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if viewModel.snapshots.count < 2 {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("Not enough data yet. TidyByte records the size once a day when you open the app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(minHeight: 120)
                    .frame(maxWidth: .infinity)
                } else {
                    let first = viewModel.snapshots.first!
                    let last = viewModel.snapshots.last!
                    let delta = last.totalBytes - first.totalBytes
                    let summary = delta == 0
                        ? "No change \(trendSpanLabel)"
                        : delta > 0
                        ? "Library grew by \(delta.formattedFileSize) \(trendSpanLabel)"
                        : "Library shrank by \(abs(delta).formattedFileSize) \(trendSpanLabel)"

                    Chart(viewModel.snapshots) { snapshot in
                        LineMark(
                            x: .value("Date", snapshot.capturedAt),
                            y: .value("Size", snapshot.totalBytes)
                        )
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: trendDomain)
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
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Library size chart")
                    .accessibilityValue("\(summary). Now \(last.totalBytes.formattedFileSize).")

                    HStack {
                        Image(systemName: delta == 0 ? "equal" : delta > 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(summary)
                            .font(.caption)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                    Text("This is library size, not free space on the iPhone.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Cleanup Opportunities

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

    // MARK: - Action Handling

    /// Central dispatcher for all Storage‑initiated actions.
    private func handle(_ action: StorageAction) {
        switch action {
        case .cleanup(let tool):
            appNavigation.showCleanup(tool: tool)
        case .swipe(let filter):
            appNavigation.showSwipeSession(filter: filter)
        case .activity:
            appNavigation.showActivity()
        }
    }
}
