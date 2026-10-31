import MacOSCleanerCore
import SwiftUI

/// Radial mind map: the scan root sits at the center and top-level groups
/// fan out as branches with size labels and connector lines.
/// Renders entirely from already-scanned `FileRecord` values.
struct MindMapView: View {
    @Bindable var model: AppViewModel
    var files: [FileRecord]
    var grouping: ExploreGrouping
    var maxDepth: Int
    var nameFilter: String

    @State private var selectedID: String?
    private let branchLimit = 10

    private var filtered: [FileRecord] {
        ExploreTreeBuilder.filteredFiles(files, nameFilter: nameFilter)
    }

    private var groups: [ExploreGroup] {
        let roots = ExploreTreeBuilder.build(files: filtered, grouping: grouping, maxDepth: maxDepth)
        return Array(roots.sorted { $0.bytes > $1.bytes }.prefix(branchLimit))
    }

    private var totalBytes: Int64 {
        groups.reduce(Int64(0)) { $0 + max(0, $1.bytes) }
    }

    /// Node centers in unit space; index 0 is the center root.
    private func nodePositions(count: Int) -> [CGPoint] {
        guard count > 0 else {
            return []
        }
        if count == 1 {
            return [CGPoint(x: 0.5, y: 0.28)]
        }
        return (0..<count).map { index in
            let angle = (Double(index) / Double(count)) * 2 * Double.pi - Double.pi / 2
            return CGPoint(
                x: 0.5 + 0.34 * CGFloat(cos(angle)),
                y: 0.5 + 0.34 * CGFloat(sin(angle))
            )
        }
    }

    var body: some View {
        VStack(spacing: Spacing.elementNormal) {
            if groups.isEmpty {
                ExploreEmptyState()
            } else {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    let height: CGFloat = 300
                    let positions = nodePositions(count: groups.count)
                    let center = CGPoint(x: width / 2, y: height / 2)
                    ZStack {
                        ConnectorLinesView(
                            center: center,
                            targets: groups.enumerated().map { index, _ in
                                CGPoint(x: positions[index].x * width, y: positions[index].y * height)
                            },
                            groups: groups
                        )
                        .frame(width: width, height: height)
                        rootNode(at: center)
                        ForEach(groups) { group in
                            if let index = groups.firstIndex(of: group) {
                                branchNode(
                                    group,
                                    at: CGPoint(x: positions[index].x * width, y: positions[index].y * height)
                                )
                            }
                        }
                    }
                    .frame(width: width, height: height)
                }
                .frame(height: 300)
                if let selected = groups.first(where: { $0.id == selectedID }) {
                    selectedFooter(for: selected)
                }
            }
        }
        .onChange(of: ExploreFilesToken(files)) { _, _ in
            selectedID = nil
        }
    }

    private func rootNode(at center: CGPoint) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "internaldrive")
                .foregroundStyle(Primary.primary)
            Text(totalBytes.formattedByteCount)
                .appFont(.labelMedium)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .background(
            Color(nsColor: .textBackgroundColor),
            in: Circle()
        )
        .overlay(Circle().stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .position(center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Scan total: \(totalBytes.formattedByteCount)"))
    }

    private func branchNode(_ group: ExploreGroup, at point: CGPoint) -> some View {
        let palette = ExploreChartPalette.palette(for: group)
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
            VStack(spacing: 2) {
                Text(group.name)
                    .appFont(.labelMedium)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(group.bytes.formattedByteCount)
                    .appFont(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if group.fileCount > 0 {
                    Text(String(localized: "\(group.fileCount) files", comment: "Explore group file count"))
                        .appFont(.caption)
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: 150)
            .background(palette.soft, in: RoundedRectangle(cornerRadius: Radius.cardCompact, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.cardCompact, style: .continuous).strokeBorder(.tint, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .position(point)
        .help("\(group.name), \(group.bytes.formattedByteCount)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(group.name), \(group.bytes.formattedByteCount), \(group.fileCount) files"))
        .accessibilityHint(String(localized: "Shows group details"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectedFooter(for group: ExploreGroup) -> some View {
        VStack(alignment: .leading, spacing: Spacing.elementTight) {
            HStack {
            Text(group.name)
                .appFont(.caption)
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("\(group.bytes.formattedByteCount) · \(group.fileCount) files")
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
            ExploreGroupActionsView(model: model, group: group, files: filtered)
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, Spacing.elementTight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Selected: \(group.name), \(group.bytes.formattedByteCount)"))
    }
}

private struct ConnectorLinesView: View {
    var center: CGPoint
    var targets: [CGPoint]
    var groups: [ExploreGroup]

    var body: some View {
        ZStack {
            ForEach(Array(targets.enumerated()), id: \.offset) { index, target in
                let group = index < groups.count ? groups[index] : nil
                ConnectorLineShape(center: center, target: target)
                    .stroke(
                        ExploreChartPalette.palette(for: group).mid.opacity(0.85),
                        lineWidth: 0.5
                    )
            }
        }
    }
}

private struct ConnectorLineShape: Shape {
    var center: CGPoint
    var target: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x - rect.origin.x, y: center.y - rect.origin.y))
        path.addLine(to: CGPoint(x: target.x - rect.origin.x, y: target.y - rect.origin.y))
        return path
    }
}
