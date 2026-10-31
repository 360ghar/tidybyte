import MacOSCleanerCore
import SwiftUI

/// Concentric-ring sunburst: the full circle is total size, inner rings are
/// top-level groups, outer rings are their children.
/// Renders entirely from already-scanned `FileRecord` values.
struct SunburstView: View {
    @Bindable var model: AppViewModel
    var files: [FileRecord]
    var grouping: ExploreGrouping
    var maxDepth: Int
    var nameFilter: String

    @State private var selectedID: String?

    private var filtered: [FileRecord] {
        ExploreTreeBuilder.filteredFiles(files, nameFilter: nameFilter)
    }

    private var groups: [ExploreGroup] {
        ExploreTreeBuilder.build(files: filtered, grouping: grouping, maxDepth: maxDepth)
    }

    private var sectors: [SunburstSector] {
        ExploreTreeBuilder.sectors(groups: groups, maxDepth: maxDepth)
    }

    private var totalBytes: Int64 {
        groups.reduce(Int64(0)) { $0 + max(0, $1.bytes) }
    }

    private var selectedSector: SunburstSector? {
        sectors.first { $0.id == selectedID }
    }

    private var selectedGroup: ExploreGroup? {
        guard let sector = selectedSector else {
            return nil
        }
        let baseID = sector.id.split(separator: "#").first.map(String.init) ?? sector.id
        return groups.first { $0.id == baseID }
    }

    var body: some View {
        VStack(spacing: Spacing.elementNormal) {
            if sectors.isEmpty {
                ExploreEmptyState()
            } else {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, 280)
                    ZStack {
                        ForEach(sectors) { sector in
                            sectorSlice(sector, canvas: side)
                        }
                        VStack(spacing: 2) {
                            Text(totalBytes.formattedByteCount)
                                .appFont(.h4)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(String(localized: "\(groups.count) groups", comment: "Sunburst center group count"))
                                .appFont(.caption)
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: side * 0.34)
                        .allowsHitTesting(false)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(String(localized: "Total \(totalBytes.formattedByteCount) in \(groups.count) groups"))
                    }
                    .frame(width: proxy.size.width, height: 300, alignment: .center)
                }
                .frame(height: 300)
                legend
            }
        }
        .onChange(of: ExploreFilesToken(files)) { _, _ in
            selectedID = nil
        }
    }

    private func sectorSlice(_ sector: SunburstSector, canvas: CGFloat) -> some View {
        let ringDepth = max(1, min(sector.depth, max(1, maxDepth)))
        let ringCount = CGFloat(max(1, maxDepth))
        let outerRadius = (canvas / 2) * (CGFloat(ringDepth) / ringCount)
        // Ring 1 starts outside the center readout circle.
        let innerRadius = ringDepth == 1 ? (canvas / 2) * 0.22 : (canvas / 2) * (CGFloat(ringDepth - 1) / ringCount)
        let startAngle = Angle.degrees(-90 + sector.startFraction * 360)
        let endAngle = Angle.degrees(-90 + sector.endFraction * 360)
        let palette = ExploreChartPalette.palette(for: sector)
        let isSelected = selectedID == sector.id
        return RingSegment(
            innerRadius: innerRadius,
            outerRadius: max(innerRadius + 2, outerRadius - 1.5),
            startAngle: startAngle,
            endAngle: endAngle
        )
        .fill(isSelected ? palette.mid : palette.mid.opacity(sector.depth == 1 ? 0.9 : 0.62))
        .overlay(
            RingSegment(
                innerRadius: innerRadius,
                outerRadius: max(innerRadius + 2, outerRadius - 1.5),
                startAngle: startAngle,
                endAngle: endAngle
            )
            .stroke(
                isSelected ? Color.primary : Color(nsColor: .windowBackgroundColor),
                lineWidth: isSelected ? 2 : 1
            )
        )
        .onTapGesture { toggle(sector, isSelected: isSelected) }
        .help("\(sector.name), \(sector.bytes.formattedByteCount)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(sector.name), \(sector.bytes.formattedByteCount), depth \(sector.depth)"))
        .accessibilityHint(String(localized: "Selects this segment"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { toggle(sector, isSelected: isSelected) }
    }

    /// Pointer and VoiceOver share one path; the segment list below the chart
    /// gives keyboard users the same selection.
    private func toggle(_ sector: SunburstSector, isSelected: Bool) {
        let next = isSelected ? nil : sector.id
        selectedID = next
        selectRecordForSectorID(next)
    }

    private func selectRecordForSectorID(_ sectorID: String?) {
        guard let sectorID,
              let sector = sectors.first(where: { $0.id == sectorID }),
              let baseID = sector.id.split(separator: "#").first.map(String.init),
              let group = groups.first(where: { $0.id == baseID }),
              let record = ExploreTreeBuilder.largestMember(of: group, in: filtered) else {
            if sectorID == nil {
                model.selectExploreRecord(id: nil)
            }
            return
        }
        model.selectExploreRecord(id: record.id)
    }

    private var legend: some View {
        VStack(spacing: Spacing.elementTight) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: Spacing.elementTight)],
                spacing: Spacing.elementTight
            ) {
                ForEach(Array(groups.prefix(8))) { group in
                    Button {
                        let next = selectedID == "\(group.id)#1" ? nil : "\(group.id)#1"
                        selectedID = next
                        selectRecordForSectorID(next)
                    } label: {
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
                    }
                    .buttonStyle(.plain)
                    .help("\(group.name), \(group.bytes.formattedByteCount)")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(group.name), \(group.bytes.formattedByteCount)"))
                }
            }
            if let selected = selectedSector {
                HStack {
                    Text(selected.name)
                        .appFont(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(selected.bytes.formattedByteCount)
                        .appFont(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.secondary)
                    Button(String(localized: "Clear", comment: "Explore clear selection")) {
                        selectedID = nil
                        model.selectExploreRecord(id: nil)
                    }
                    .buttonStyle(.plain)
                    .appFont(.caption)
                    .foregroundStyle(Color.secondary)
                }
                .padding(.horizontal, Spacing.cardPadding)
                .padding(.vertical, Spacing.elementTight)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "Selected: \(selected.name), \(selected.bytes.formattedByteCount)"))
                if let selectedGroup {
                    ExploreGroupActionsView(model: model, group: selectedGroup, files: filtered)
                }
            }
        }
    }
}

/// Annular segment used by the sunburst; tiny sweeps collapse to a thin arc
/// so hairline sectors never crash the path renderer.
private struct RingSegment: Shape {
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let safeInner = max(0, innerRadius)
        let safeOuter = max(safeInner + 1, outerRadius)
        let sweep = endAngle.degrees - startAngle.degrees
        let effectiveEnd = sweep < 0.5
            ? Angle.degrees(startAngle.degrees + 0.5)
            : endAngle
        path.addArc(center: center, radius: safeOuter, startAngle: startAngle, endAngle: effectiveEnd, clockwise: false)
        path.addArc(center: center, radius: safeInner, startAngle: effectiveEnd, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}
