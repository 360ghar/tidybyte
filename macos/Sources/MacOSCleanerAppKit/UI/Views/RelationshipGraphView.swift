import MacOSCleanerCore
import SwiftUI

/// A view that displays project relationships as a simple graph visualization.
/// Shows connections between files based on their relationship edges (duplicates, generated files, etc.).
struct RelationshipGraphView: View {
    @Bindable var model: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let edges: [RelationshipEdge]
    let filesByID: [String: FileRecord]

    @State private var hoveredNode: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if edges.isEmpty {
                emptyState
            } else {
                graphContent
            }
        }
        .padding(Spacing.cardPadding)
    }

    private var header: some View {
        HStack(spacing: Spacing.elementTight) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(Primary.primary)
                .accessibilityHidden(true)
            Text(String(localized: "Project Relationships", comment: "Relationship graph header"))
                .font(.app(.h3))
                
                .foregroundStyle(Color.primary)
            Spacer()
            Text(String(localized: "\(edges.count) connections", comment: "Relationship edge count"))
                .appFont(.labelMedium)
                
                .foregroundStyle(Color.secondary)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                String(localized: "No relationships detected yet.", comment: "Empty relationship graph message"),
                systemImage: "point.3.connected.trianglepath.dotted")
        } description: {
            Text(String(localized: "Run a scan to discover file connections.", comment: "Empty relationship graph hint"))
        } actions: {
            EmptyStateActionsView(model: model)
        }
    }

    private var graphContent: some View {
        VStack(spacing: 8) {
            // Single horizontal ScrollView: a nested inner ScrollView previously
            // made the graph nearly unscrollable, so the canvas scrolls with the
            // outer scroll area only.
            ScrollView(.horizontal, showsIndicators: false) {
                canvas
                    .frame(minWidth: 400, minHeight: 240)
            }
            edgeLegend
        }
    }

    private var edgeLegend: some View {
        let presentTypes = Array(Set(edges.map(\.edgeType))).sorted { $0.rawValue < $1.rawValue }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.elementNormal) {
                ForEach(presentTypes, id: \.self) { type in
                    HStack(spacing: 4) {
                        edgeSwatch(for: type)
                        Text(edgeDisplayName(for: type))
                            .appFont(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
    }

    private func edgeSwatch(for type: RelationshipEdgeType) -> some View {
        let dash = edgeDash(for: type)
        return Path { path in
            path.move(to: CGPoint(x: 0, y: 4))
            path.addLine(to: CGPoint(x: 18, y: 4))
        }
        .stroke(
            edgeColor(for: type),
            style: StrokeStyle(lineWidth: 0.5, dash: dash)
        )
        .frame(width: 18, height: 8)
        .accessibilityHidden(true)
    }

    private func edgeDisplayName(for type: RelationshipEdgeType) -> String {
        switch type {
        case .duplicate: return String(localized: "Duplicate")
        case .generatedFrom: return String(localized: "Generated From")
        case .sameProject: return String(localized: "Same Project")
        case .exportOf: return String(localized: "Export Of")
        case .backupOf: return String(localized: "Backup Of")
        case .versionOf: return String(localized: "Version Of")
        case .manifestOf: return String(localized: "Manifest Of")
        case .temporaryArtifactOf: return String(localized: "Temporary Artifact")
        case .nearDuplicateOf: return String(localized: "Near Duplicate")
        case .cloudCopyOf: return String(localized: "Cloud Copy")
        }
    }

    private var canvas: some View {
        GeometryReader { geometry in
            let nodes = calculateNodePositions(in: geometry.size)
            ZStack {
                // Draw edges
                ForEach(edges) { edge in
                    if let fromNode = nodes[edge.fromFileID],
                       let toNode = nodes[edge.toFileID] {
                        edgePath(
                            from: fromNode,
                            to: toNode,
                            type: edge.edgeType,
                            isHighlighted: hoveredNode == edge.fromFileID || hoveredNode == edge.toFileID
                        )
                    }
                }

                // Draw nodes
                ForEach(Array(nodes.keys), id: \.self) { fileID in
                    if let position = nodes[fileID],
                       let record = filesByID[fileID] {
                        nodeView(for: record, at: position)
                    }
                }
            }
        }
    }

    private func calculateNodePositions(in size: CGSize) -> [String: CGPoint] {
        var positions: [String: CGPoint] = [:]
        let uniqueFiles = Set(edges.flatMap { [$0.fromFileID, $0.toFileID] })
        let fileList = Array(uniqueFiles)

        guard !fileList.isEmpty else { return positions }

        let safeWidth = max(CGFloat(1), size.width)
        let safeHeight = max(CGFloat(1), size.height)
        let cols = Int(ceil(sqrt(Double(fileList.count))))
        let spacingX = safeWidth / CGFloat(cols + 1)
        let rows = Int(ceil(Double(fileList.count) / Double(cols)))
        let spacingY = safeHeight / CGFloat(rows + 1)

        for (index, fileID) in fileList.enumerated() {
            let col = index % cols
            let row = index / cols
            let x = spacingX * CGFloat(col + 1)
            let y = spacingY * CGFloat(row + 1)
            positions[fileID] = CGPoint(x: x, y: y)
        }

        return positions
    }

    private func edgePath(from: CGPoint, to: CGPoint, type: RelationshipEdgeType, isHighlighted: Bool) -> some View {
        Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(
            edgeColor(for: type),
            style: StrokeStyle(
                lineWidth: isHighlighted ? 1 : 0.5,
                dash: edgeDash(for: type)
            )
        )
        .opacity(isHighlighted ? 1.0 : 0.6)
        .animation(reduceMotion ? nil : .appSelection, value: isHighlighted)
    }

    private func edgeColor(for type: RelationshipEdgeType) -> Color {
        switch type {
        case .duplicate: return SemanticScale.error
        case .nearDuplicateOf: return SemanticScale.error
        case .generatedFrom: return Primary.primary
        case .sameProject: return SemanticScale.success
        case .exportOf: return SemanticScale.warning
        case .backupOf: return CategoricalPalette.pink.mid
        case .versionOf: return CategoricalPalette.purple.mid
        case .manifestOf: return CategoricalPalette.orange.mid
        case .temporaryArtifactOf: return CategoricalPalette.yellow.mid
        case .cloudCopyOf: return CategoricalPalette.teal.mid
        }
    }

    private func edgeDash(for type: RelationshipEdgeType) -> [CGFloat] {
        switch type {
        case .duplicate, .nearDuplicateOf: return []
        case .generatedFrom, .temporaryArtifactOf: return [5, 3]
        default: return [8, 4]
        }
    }

    private func nodeView(for record: FileRecord, at position: CGPoint) -> some View {
        let isHovered = hoveredNode == record.id
        return VStack(spacing: 2) {
            Image(systemName: nodeIcon(for: record))
                .font(.caption)
                .foregroundStyle(nodeColor(for: record))
            Text(record.fileName)
                .appFont(.labelMedium)
                .lineLimit(1)
                .foregroundStyle(Color.primary)
                .frame(width: 80)
        }
        .padding(4)
        .background(
            isHovered ? AnyShapeStyle(Primary.selection) : AnyShapeStyle(.background.secondary),
            in: RoundedRectangle(cornerRadius: Radius.cardCompact, style: .continuous))
        
        .position(position)
        .onHover { isHovered in
            withAnimation(reduceMotion ? nil : .appSelection) {
                hoveredNode = isHovered ? record.id : nil
            }
        }
        .help(record.fileName)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(record.fileName))
        .accessibilityHint(String(localized: "File relationship node"))
    }

    private func nodeIcon(for record: FileRecord) -> String {
        switch record.kind {
        case .directory: return "folder.fill"
        case .package: return "folder.badge.gearshape"
        case .symlink: return "arrow.triangle.turn.up.right.diamond"
        default: return "doc.fill"
        }
    }

    private func nodeColor(for record: FileRecord) -> Color {
        if record.riskFlags.contains(.protectedFile) || record.riskFlags.contains(.protectedDirectory) {
            return SemanticScale.error
        }
        if record.cloudProvider != nil {
            return CategoricalPalette.teal.mid
        }
        return Primary.primary
    }
}
