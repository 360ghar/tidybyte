import SwiftUI
import MacOSCleanerCore

struct TreemapView: View {
    var sections: [(FindingCategory, Int64)]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedBlock: SelectedBlockInfo?

    struct SelectedBlockInfo: Equatable {
        let label: String
        let bytes: Int64
        let color: Color
    }

    var body: some View {
        VStack(spacing: 0) {
            // Fixed-height canvas area so the selection panel below is always
            // visible (a greedy GeometryReader inside a VStack can otherwise
            // consume the entire parent frame and squeeze out siblings).
            GeometryReader { proxy in
                let visibleSections = Array(sections.prefix(8))
                if visibleSections.isEmpty {
                    Rectangle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            Text(String(localized: "Scan results will appear here."))
                                .appFont(.caption)
                                .foregroundStyle(Color.secondary)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.cardCompact, style: .continuous))
                } else {
                    let spacing: CGFloat = 4
                    let availableWidth = max(0, proxy.size.width)
                    let widths = Self.blockWidths(for: visibleSections, availableWidth: availableWidth, spacing: spacing)

                    HStack(spacing: spacing) {
                        ForEach(Array(visibleSections.enumerated()), id: \.offset) { index, item in
                            TreemapBlock(
                                category: item.0,
                                byteCount: item.1,
                                width: widths[index],
                                height: proxy.size.height,
                                index: index,
                                isSelected: selectedBlock?.label == item.0.displayName,
                                onSelect: {
                                    if selectedBlock?.label == item.0.displayName {
                                        selectedBlock = nil
                                    } else {
                                        selectedBlock = SelectedBlockInfo(
                                            label: item.0.displayName,
                                            bytes: item.1,
                                            color: item.0.palette.mid
                                        )
                                    }
                                }
                            )
                        }
                    }
                    .frame(width: availableWidth, alignment: .leading)
                    .clipped()
                }
            }
            .frame(height: 120)

            if let selected = selectedBlock {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(selected.color)
                            .frame(width: 10, height: 10)
                        Text(selected.label)
                            .appFont(.labelMedium)
                            
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Text(selected.bytes.formattedByteCount)
                            .appFont(.filePath)
                            .foregroundStyle(Color.secondary)
                    }
                    Button(String(localized: "Clear Selection")) { selectedBlock = nil }
                        .buttonStyle(.plain)
                        .appFont(.labelMedium)
                        .foregroundStyle(Primary.primary)
                        .underline()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: Radius.cardCompact, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .transition(.opacity)
                .animation(reduceMotion ? nil : .appSelection, value: selectedBlock)
            }
        }
        // A re-scan can drop the selected category; keeping the old selection
        // would render a stale detail panel for a block that no longer exists.
        .onChange(of: sections.map(\.0)) { _, _ in
            selectedBlock = nil
        }
    }

    private static func blockWidths(
        for sections: [(FindingCategory, Int64)],
        availableWidth: CGFloat,
        spacing: CGFloat
    ) -> [CGFloat] {
        guard !sections.isEmpty else {
            return []
        }

        let totalSpacing = spacing * CGFloat(max(0, sections.count - 1))
        let contentWidth = max(0, availableWidth - totalSpacing)
        guard contentWidth > 0 else {
            return Array(repeating: CGFloat(0), count: sections.count)
        }
        let minimumWidth = min(CGFloat(72), max(CGFloat(32), contentWidth / CGFloat(sections.count)))
        let total = max(1, sections.reduce(Int64(0)) { $0 + max(0, $1.1) })
        var widths = sections.map { section in
            let ratio = Double(max(1, section.1)) / Double(total)
            return max(minimumWidth, contentWidth * CGFloat(ratio))
        }

        let overflow = widths.reduce(0, +) - contentWidth
        guard overflow > 0 else {
            return widths
        }

        let flexibleWidth = widths.reduce(CGFloat(0)) { $0 + max(0, $1 - minimumWidth) }
        guard flexibleWidth > 0 else {
            return Array(repeating: contentWidth / CGFloat(sections.count), count: sections.count)
        }

        widths = widths.map { width in
            let shrinkShare = max(0, width - minimumWidth) / flexibleWidth
            return max(minimumWidth, width - overflow * shrinkShare)
        }

        return widths
    }
}

struct TreemapBlock: View {
    let category: FindingCategory
    let byteCount: Int64
    let width: CGFloat
    let height: CGFloat
    let index: Int
    var isSelected: Bool = false
    var onSelect: (() -> Void)?

    var body: some View {
        Button(action: { onSelect?() }) {
            VStack(alignment: .leading) {
                Text(category.displayName)
                    .appFont(.labelMedium)
                    
                    .foregroundStyle(overlayLabelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                Text(byteCount.formattedByteCount)
                    .appFont(.filePath)
                    .foregroundStyle(overlayLabelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(8)
            .frame(width: width, height: height, alignment: .leading)
            .background(overlayBackgroundColor, in: RoundedRectangle(cornerRadius: Radius.cardCompact, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.cardCompact, style: .continuous).strokeBorder(.tint, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(category.displayName + ", " + byteCount.formattedByteCount))
        .accessibilityValue(isSelected ? String(localized: "Selected") : String(localized: "Not selected"))
        .accessibilityHint(String(localized: "Shows category size"))
    }

    private var overlayBackgroundColor: Color { category.palette.mid }

    /// Loud fills always carry black text; the palette ink is black in both schemes.
    private var overlayLabelColor: Color {
        category.palette.ink
    }
}
