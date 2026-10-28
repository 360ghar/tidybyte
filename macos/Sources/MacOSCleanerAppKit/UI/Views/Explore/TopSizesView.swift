import MacOSCleanerCore
import SwiftUI

/// Horizontal ranked bars of the largest groups, biggest first.
/// Renders entirely from already-scanned `FileRecord` values.
struct TopSizesView: View {
    @Bindable var model: AppViewModel
    var files: [FileRecord]
    var grouping: ExploreGrouping
    var maxDepth: Int
    var nameFilter: String

    @State private var selectedID: String?
    private let rowLimit = 20

    private var filtered: [FileRecord] {
        ExploreTreeBuilder.filteredFiles(files, nameFilter: nameFilter)
    }

    private var groups: [ExploreGroup] {
        let roots = ExploreTreeBuilder.build(files: filtered, grouping: grouping, maxDepth: maxDepth)
        return Array(roots.sorted { $0.bytes > $1.bytes }.prefix(rowLimit))
    }

    private var maxBytes: Int64 {
        groups.first?.bytes ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.elementTight) {
            if groups.isEmpty {
                ExploreEmptyState()
            } else {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    row(rank: index + 1, group: group)
                }
            }
        }
        .onChange(of: files.map(\.id)) { _, _ in
            selectedID = nil
        }
    }

    private func row(rank: Int, group: ExploreGroup) -> some View {
        let palette = ExploreChartPalette.palette(for: group)
        let fraction = maxBytes > 0 ? Double(max(0, group.bytes)) / Double(maxBytes) : 0
        let isSelected = selectedID == group.id
        return Button {
            let next = isSelected ? nil : group.id
            selectedID = next
            if next != nil, let record = ExploreTreeBuilder.largestMember(of: group, in: filtered) {
                model.selectExploreRecord(id: record.id)
            } else if next == nil {
                model.selectExploreRecord(id: nil)
            }
        } label: {
            HStack(spacing: 10) {
                Text("\(rank)")
                    .appFont(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
                    .frame(width: 22, alignment: .trailing)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(group.name)
                            .appFont(.bodyMedium)
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(group.bytes.formattedByteCount)
                            .appFont(.labelMedium)
                            .monospacedDigit()
                            .foregroundStyle(Color.secondary)
                    }
                    GeometryReader { proxy in
                        Capsule()
                            .fill(.quaternary)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(palette.mid)
                                    .frame(width: proxy.size.width * CGFloat(min(1, max(0, fraction))))
                            }
                    }
                    .frame(height: 8)
                    .accessibilityHidden(true)
                    HStack {
                        Text(String(localized: "\(group.fileCount) files", comment: "Explore group file count"))
                            .appFont(.caption)
                            .foregroundStyle(Color.secondary)
                        if let detail = group.detail, detail != group.name {
                            Text(detail)
                                .appFont(.filePath)
                                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if isSelected {
                            Spacer()
                            Button(String(localized: "Clear", comment: "Explore clear selection")) {
                                selectedID = nil
                                model.selectExploreRecord(id: nil)
                            }
                            .buttonStyle(.plain)
                            .appFont(.caption)
                            .foregroundStyle(Color.secondary)
                        }
                    }
                    if isSelected {
                        ExploreGroupActionsView(model: model, group: group, files: filtered)
                    }
                }
            }
            .padding(.horizontal, Spacing.cardPadding)
            .padding(.vertical, Spacing.elementTight)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Radius.cardCompact, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.cardCompact, style: .continuous).strokeBorder(.tint, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .help("\(group.name), \(group.bytes.formattedByteCount)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Rank \(rank): \(group.name), \(group.bytes.formattedByteCount)"))
        .accessibilityHint(String(localized: "Shows group details"))
    }
}
