import MacOSCleanerCore
import SwiftUI

/// Packed circles: each group is a circle sized by bytes, placed with a
/// deterministic spiral packer (no physics, no dependencies).
/// Renders entirely from already-scanned `FileRecord` values.
struct BubblesView: View {
    @Bindable var model: AppViewModel
    var files: [FileRecord]
    var grouping: ExploreGrouping
    var maxDepth: Int
    var nameFilter: String

    @State private var selectedID: String?
    private let bubbleLimit = 24

    private struct PlacedBubble: Identifiable, Sendable {
        var id: String
        var group: ExploreGroup
        /// Center in unit space (0..<1).
        var center: CGPoint
        var radius: CGFloat
    }

    private var filtered: [FileRecord] {
        ExploreTreeBuilder.filteredFiles(files, nameFilter: nameFilter)
    }

    private var groups: [ExploreGroup] {
        let roots = ExploreTreeBuilder.build(files: filtered, grouping: grouping, maxDepth: maxDepth)
        return Array(roots.sorted { $0.bytes > $1.bytes }.prefix(bubbleLimit))
    }

    private var totalBytes: Int64 {
        groups.reduce(Int64(0)) { $0 + max(0, $1.bytes) }
    }

    /// Deterministic largest-first spiral packing in unit space.
    private func placedBubbles() -> [PlacedBubble] {
        let total = Double(max(1, totalBytes))
        // Radius proportional to sqrt(bytes); normalized so the largest bubble
        // is ~0.24 of unit space and everything fits the canvas.
        let radii = groups.map { group -> CGFloat in
            let fraction = Double(max(0, group.bytes)) / total
            return CGFloat(0.24 * sqrt(max(0.0004, fraction)))
        }
        var placed: [PlacedBubble] = []
        for (index, group) in groups.enumerated() {
            let radius = radii[index]
            let center: CGPoint
            if index == 0 {
                center = CGPoint(x: 0.5, y: 0.5)
            } else if let spot = spiralSpot(for: radius, avoiding: placed) {
                center = spot
            } else {
                continue
            }
            placed.append(PlacedBubble(id: group.id, group: group, center: center, radius: radius))
        }
        return placed
    }

    private func spiralSpot(for radius: CGFloat, avoiding placed: [PlacedBubble]) -> CGPoint? {
        // Golden-angle spiral outward from the center; first non-overlapping
        // spot wins. Deterministic across renders for the same input.
        let goldenAngle = Double.pi * (3 - sqrt(5))
        var distance = 0.02
        var angle = 0.0
        for _ in 0..<900 {
            let candidate = CGPoint(
                x: 0.5 + CGFloat(cos(angle) * distance),
                y: 0.5 + CGFloat(sin(angle) * distance)
            )
            let inside = candidate.x - radius >= -0.01
                && candidate.x + radius <= 1.01
                && candidate.y - radius >= -0.01
                && candidate.y + radius <= 1.01
            let overlaps = placed.contains { other in
                hypot(candidate.x - other.center.x, candidate.y - other.center.y)
                    < radius + other.radius + 0.008
            }
            if inside, !overlaps {
                return candidate
            }
            angle += goldenAngle
            distance += 0.0016
            if distance > 0.75 {
                return nil
            }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: Spacing.elementNormal) {
            if groups.isEmpty {
                ExploreEmptyState()
            } else {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height, 340)
                    let bubbles = placedBubbles()
                    let xOffset = (proxy.size.width - side) / 2
                    ZStack {
                        ForEach(bubbles) { bubble in
                            bubbleView(bubble, canvas: side, xOffset: xOffset)
                        }
                    }
                    .frame(width: proxy.size.width, height: max(side, 200))
                }
                .frame(minHeight: 220, maxHeight: 360)
                if let selected = groups.first(where: { $0.id == selectedID }) {
                    selectedFooter(for: selected)
                }
            }
        }
        .onChange(of: ExploreFilesToken(files)) { _, _ in
            selectedID = nil
        }
    }

    private func bubbleView(_ bubble: PlacedBubble, canvas: CGFloat, xOffset: CGFloat) -> some View {
        let palette = ExploreChartPalette.palette(for: bubble.group)
        let diameter = max(14, bubble.radius * 2 * canvas)
        let isSelected = selectedID == bubble.id
        let showsLabel = diameter > 56
        return Button {
            let next = isSelected ? nil : bubble.id
            selectedID = next
            if let next, let group = groups.first(where: { $0.id == next }),
               let record = ExploreTreeBuilder.largestMember(of: group, in: filtered) {
                model.selectExploreRecord(id: record.id)
            } else if next == nil {
                model.selectExploreRecord(id: nil)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(palette.mid.opacity(0.82))
                if showsLabel {
                    VStack(spacing: 1) {
                        Text(bubble.group.name)
                            .appFont(.caption)
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 6)
                        Text(bubble.group.bytes.formattedByteCount)
                            .appFont(.caption)
                            .monospacedDigit()
                            .foregroundStyle(palette.ink.opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            .frame(width: diameter, height: diameter)
            .overlay(
                Circle()
                    .stroke(
                        Color.primary,
                        lineWidth: isSelected ? 1 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .position(x: xOffset + bubble.center.x * canvas, y: bubble.center.y * canvas)
        .help("\(bubble.group.name), \(bubble.group.bytes.formattedByteCount)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(bubble.group.name), \(bubble.group.bytes.formattedByteCount)"))
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
