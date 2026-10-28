import MacOSCleanerCore
import SwiftUI

/// Icicle / flame chart: one horizontal row per depth level, segment widths
/// proportional to bytes. Click-to-zoom narrows the chart to a group's share.
/// Renders entirely from already-scanned `FileRecord` values.
struct FlameView: View {
    @Bindable var model: AppViewModel
    var files: [FileRecord]
    var grouping: ExploreGrouping
    var maxDepth: Int
    var nameFilter: String

    @State private var zoomedGroupID: String?

    private var filtered: [FileRecord] {
        ExploreTreeBuilder.filteredFiles(files, nameFilter: nameFilter)
    }

    private var groups: [ExploreGroup] {
        ExploreTreeBuilder.build(files: filtered, grouping: grouping, maxDepth: maxDepth)
    }

    /// When zoomed, the selected top-level group becomes the whole chart.
    private var chartGroups: [ExploreGroup] {
        guard let zoomed = zoomedGroupID else {
            return groups
        }
        if let match = groups.first(where: { topLevelID(of: $0) == zoomed }) {
            return [match]
        }
        return groups
    }

    private var rows: [[SunburstSector]] {
        ExploreTreeBuilder.flameRows(groups: chartGroups, maxDepth: maxDepth)
    }

    private func topLevelID(of group: ExploreGroup) -> String {
        "\(group.id)#1"
    }

    private var zoomedGroup: ExploreGroup? {
        guard let zoomed = zoomedGroupID else {
            return nil
        }
        return groups.first { topLevelID(of: $0) == zoomed }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.elementNormal) {
            if groups.isEmpty {
                ExploreEmptyState()
            } else {
                if zoomedGroupID != nil {
                    zoomBanner
                }
                GeometryReader { proxy in
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                            flameRow(row, rowIndex: rowIndex, width: proxy.size.width)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(minHeight: 220, maxHeight: 320)
                if let zoomedGroup {
                    ExploreGroupActionsView(model: model, group: zoomedGroup, files: filtered)
                }
                legend
            }
        }
        .onChange(of: files.map(\.id)) { _, _ in
            zoomedGroupID = nil
        }
    }

    private var zoomBanner: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.secondary)
            Text(zoomedGroup?.name ?? "")
                .appFont(.caption)
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(String(localized: "Zoom out", comment: "Flame chart zoom out")) {
                zoomedGroupID = nil
            }
            .buttonStyle(.plain)
            .appFont(.caption)
            .foregroundStyle(Color.secondary)
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, Spacing.elementTight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Zoomed into \(zoomedGroup?.name ?? "")"))
    }

    private func flameRow(_ row: [SunburstSector], rowIndex: Int, width: CGFloat) -> some View {
        // Gaps consume width too; distribute only what remains so the row
        // never overflows its container.
        let gapTotal = CGFloat(max(0, row.count - 1)) * 1.5
        let usable = max(0, width - gapTotal)
        return HStack(spacing: 1.5) {
            ForEach(row) { sector in
                flameSegment(sector, rowWidth: usable, isTopRow: rowIndex == 0)
            }
        }
        .frame(height: 34)
    }

    private func flameSegment(_ sector: SunburstSector, rowWidth: CGFloat, isTopRow: Bool) -> some View {
        let palette = ExploreChartPalette.palette(for: sector)
        let fraction = max(0, sector.sweepFraction)
        let segmentWidth = max(2, rowWidth * CGFloat(fraction))
        let showsLabel = segmentWidth > 64
        return Button {
            if isTopRow {
                let topID = sector.id
                let next = zoomedGroupID == topID ? nil : topID
                zoomedGroupID = next
                if let next, let group = groups.first(where: { topLevelID(of: $0) == next }),
                   let record = ExploreTreeBuilder.largestMember(of: group, in: filtered) {
                    model.focusExploreRecord(id: record.id)
                    model.selectExploreRecord(id: record.id)
                } else if next == nil {
                    model.focusExploreRecord(id: nil)
                }
            }
        } label: {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(palette.mid.opacity(sector.depth == 1 ? 1.0 : 0.78))
                    .padding(0.5)
                if showsLabel {
                    Text(sector.name)
                        .appFont(.caption)
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6)
                }
            }
            .frame(width: segmentWidth, height: 34)
        }
        .buttonStyle(.plain)
        .disabled(!isTopRow)
        .help("\(sector.name), \(sector.bytes.formattedByteCount)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(sector.name), \(sector.bytes.formattedByteCount), depth \(sector.depth)"))
        .accessibilityHint(isTopRow
            ? String(localized: "Zooms into this group")
            : String(localized: "Shows segment size"))
    }

    private var legend: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: Spacing.elementTight)],
            spacing: Spacing.elementTight
        ) {
            ForEach(Array(groups.prefix(8))) { group in
                HStack(spacing: 6) {
                    Circle()
                        .fill(ExploreChartPalette.palette(for: group).mid)
                        .frame(width: 8, height: 8)
                    Text(group.name)
                        .appFont(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Text(group.bytes.formattedByteCount)
                        .appFont(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.secondary)
                }
                .help("\(group.name), \(group.bytes.formattedByteCount)")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(group.name), \(group.bytes.formattedByteCount)"))
            }
        }
    }
}
