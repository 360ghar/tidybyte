import MacOSCleanerCore
import SwiftUI

/// Timeline of when files were last touched: per-month heat grid plus a
/// spotlight list of big files untouched for a long time.
/// Renders entirely from already-scanned `FileRecord` values.
struct AgeMapView: View {
    @Bindable var model: AppViewModel
    var files: [FileRecord]
    var nameFilter: String

    @State private var selectedMonthKey: String?
    private let monthCount = 12
    private let untouchedLimit = 10

    private struct MonthBucket: Identifiable, Sendable {
        var id: String
        var label: String
        var bytes: Int64
        var fileCount: Int
    }

    private var filtered: [FileRecord] {
        ExploreTreeBuilder.filteredFiles(files, nameFilter: nameFilter)
    }

    private var monthBuckets: [MonthBucket] {
        let calendar = Calendar.current
        let now = Date()
        let monthFormatter = DateFormatter()
        monthFormatter.setLocalizedDateFormatFromTemplate("MMM yy")
        var buckets: [MonthBucket] = []
        for offset in stride(from: monthCount - 1, through: 0, by: -1) {
            guard let monthStart = calendar.date(
                byAdding: .month,
                value: -offset,
                to: calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            ) else {
                continue
            }
            let rangeStart = calendar.startOfDay(for: monthStart)
            guard let rangeEnd = calendar.date(byAdding: .month, value: 1, to: rangeStart) else {
                continue
            }
            let members = filtered.filter { file in
                guard let touched = ExploreTreeBuilder.lastTouchedDate(for: file) else {
                    return false
                }
                return touched >= rangeStart && touched < rangeEnd
            }
            let key = "\(calendar.component(.year, from: rangeStart))-\(calendar.component(.month, from: rangeStart))"
            buckets.append(MonthBucket(
                id: key,
                label: monthFormatter.string(from: rangeStart),
                bytes: members.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) },
                fileCount: members.count
            ))
        }
        return buckets
    }

    private var undatedCount: Int {
        filtered.filter { ExploreTreeBuilder.lastTouchedDate(for: $0) == nil }.count
    }

    private var maxBucketBytes: Int64 {
        monthBuckets.map(\.bytes).max() ?? 1
    }

    private var spotlight: [FileRecord] {
        ExploreTreeBuilder.bigUntouchedFiles(in: filtered, limit: untouchedLimit)
    }

    private var selectedBucket: MonthBucket? {
        monthBuckets.first { $0.id == selectedMonthKey }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.elementNormal) {
            if filtered.isEmpty {
                ExploreEmptyState()
            } else {
                heatGrid
                if let selected = selectedBucket {
                    selectedFooter(for: selected)
                }
                spotlightSection
            }
        }
        .onChange(of: files.map(\.id)) { _, _ in
            selectedMonthKey = nil
        }
    }

    private var heatGrid: some View {
        VStack(alignment: .leading, spacing: Spacing.elementTight) {
            Text(String(localized: "Touched per month", comment: "Age Map heat grid title"))
                .appFont(.labelMedium)
                .foregroundStyle(Color.secondary)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6),
                spacing: 6
            ) {
                ForEach(monthBuckets) { bucket in
                    monthCell(for: bucket)
                }
            }
            if undatedCount > 0 {
                Text(String(localized: "\(undatedCount) files have no known date", comment: "Age Map undated files note"))
                    .appFont(.caption)
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    private func monthCell(for bucket: MonthBucket) -> some View {
        let intensity = maxBucketBytes > 0
            ? Double(max(0, bucket.bytes)) / Double(maxBucketBytes)
            : 0
        let isSelected = selectedMonthKey == bucket.id
        return Button {
            selectedMonthKey = isSelected ? nil : bucket.id
        } label: {
            VStack(spacing: 2) {
                Text(bucket.label)
                    .appFont(.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(bucket.bytes.formattedByteCount)
                    .appFont(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(4)
            .background(
                bucket.bytes > 0
                    ? AnyShapeStyle(SemanticScale.warningSoft.opacity(0.25 + 0.75 * intensity))
                    : AnyShapeStyle(.quaternary),
                in: RoundedRectangle(cornerRadius: Radius.cardCompact, style: .continuous)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.cardCompact, style: .continuous).strokeBorder(.tint, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .help("\(bucket.label), \(bucket.bytes.formattedByteCount), \(bucket.fileCount) files")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(bucket.label): \(bucket.bytes.formattedByteCount), \(bucket.fileCount) files"))
        .accessibilityHint(String(localized: "Shows month details"))
    }

    private func selectedFooter(for bucket: MonthBucket) -> some View {
        HStack {
            Text(bucket.label)
                .appFont(.caption)
                .foregroundStyle(Color.secondary)
            Spacer()
            Text("\(bucket.bytes.formattedByteCount) · \(bucket.fileCount) files")
                .appFont(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
            Button(String(localized: "Clear", comment: "Explore clear selection")) {
                selectedMonthKey = nil
            }
            .buttonStyle(.plain)
            .appFont(.caption)
            .foregroundStyle(Color.secondary)
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, Spacing.elementTight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Selected month: \(bucket.label), \(bucket.bytes.formattedByteCount)"))
    }

    private var spotlightSection: some View {
        VStack(alignment: .leading, spacing: Spacing.elementTight) {
            HStack {
                Image(systemName: "moon.zzz")
                    .foregroundStyle(SemanticScale.warning)
                Text(String(localized: "Big and untouched (180+ days)", comment: "Age Map spotlight title"))
                    .appFont(.labelMedium)
                    .foregroundStyle(Color.secondary)
                Spacer()
            }
            if spotlight.isEmpty {
                Text(String(localized: "No large untouched files found. Everything big was opened recently.", comment: "Age Map spotlight empty"))
                    .appFont(.caption)
                    .foregroundStyle(Color.secondary)
            } else {
                ForEach(spotlight) { file in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(file.fileName)
                                .appFont(.bodyMedium)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            if let touched = ExploreTreeBuilder.lastTouchedDate(for: file) {
                                Text(touched.formatted(date: .abbreviated, time: .omitted))
                                    .appFont(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                            Text(file.sizeBytes.formattedByteCount)
                                .appFont(.labelMedium)
                                .monospacedDigit()
                                .foregroundStyle(Color.secondary)
                        }
                        HStack(spacing: Spacing.elementTight) {
                            SecondaryButton(
                                title: String(localized: "Focus"),
                                icon: "scope",
                                action: {
                                    model.focusExploreRecord(id: file.id)
                                    model.selectExploreRecord(id: file.id)
                                }
                            )
                            if model.stagedExploreAction(matching: file) != nil {
                                SecondaryButton(
                                    title: String(localized: "Approve"),
                                    icon: "checkmark",
                                    action: {
                                        guard let staged = model.stagedExploreAction(matching: file) else {
                                            return
                                        }
                                        model.approve(staged)
                                    }
                                )
                            } else {
                                SecondaryButton(
                                    title: String(localized: "Stage"),
                                    icon: "plus.circle",
                                    action: {
                                        _ = model.stageExploreRecordForCleanup(file)
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.cardPadding)
                    .padding(.vertical, 6)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: Radius.cardCompact, style: .continuous))
                    .overlay {
                        if model.selectedExploreRecordID == file.id {
                            RoundedRectangle(cornerRadius: Radius.cardCompact, style: .continuous).strokeBorder(.tint, lineWidth: 2)
                        }
                    }
                    .help("\(file.fileName), \(file.sizeBytes.formattedByteCount)")
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(Text("\(file.fileName), \(file.sizeBytes.formattedByteCount)"))
                }
            }
        }
    }
}
