import SwiftUI

// Shared controls for the group tools (Duplicates, Similar Photos, Bursts), so
// all three behave the same: tap a thumbnail to preview it, tap the circle to
// mark it for deletion, and the keeper carries a visible "Keep" mark.

/// Circle that marks one photo for deletion. The glyph is small, the tap
/// target is 44 pt, so a miss does not open the preview instead.
struct DeleteToggle: View {
    let isMarked: Bool
    let action: () -> Void

    var body: some View {
        Button {
            HapticHelper.selection()
            action()
        } label: {
            Image(systemName: isMarked ? "checkmark.circle.fill" : "circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(isMarked ? Color.destructive : .white)
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                .padding(Spacing.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMarked ? "Marked for deletion" : "Not marked for deletion")
        .accessibilityHint(isMarked ? "Double-tap to keep this photo" : "Double-tap to mark this photo for deletion")
        .accessibilityAddTraits(isMarked ? .isSelected : [])
    }
}

/// Selection circle for the list and grid tools (Large Files, Screenshots,
/// Blurry, Smart Categories). `overPhoto` draws it white with a shadow, for a
/// grid cell.
struct SelectToggle: View {
    let isSelected: Bool
    /// Spoken noun, e.g. "photo" → "Select photo".
    let itemName: String
    var overPhoto = true
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            HapticHelper.selection()
            action()
        } label: {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? .blue : (overPhoto ? .white : .secondary))
                .shadow(color: .black.opacity(overPhoto ? 0.4 : 0), radius: 3)
                .padding(overPhoto ? Spacing.sm : 0)
                .scaleEffect(isSelected ? 1.0 : 0.9)
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
                // 44-pt target, matching `DeleteToggle`: without it the list
                // variant is only the intrinsic symbol size, so a miss lands on
                // the row preview instead of toggling the selection.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "Deselect \(itemName)" : "Select \(itemName)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Plain "Keep" line under the keeper. No pill behind it.
struct KeeperMark: View {
    var reason: String?

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            Text(reason.map { "Keep: \($0)" } ?? "Keep")
                .foregroundStyle(.primary)
        }
        .font(.caption2.bold())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// Text button under a non-keeper that makes it the keeper.
struct MakeKeeperButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            HapticHelper.selection()
            action()
        } label: {
            Text("Keep This")
                .font(.caption2.bold())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityLabel("Keep this photo instead")
    }
}

/// Full-screen preview target for `fullScreenCover(item:)`.
struct GroupPreviewContext: Identifiable {
    let id = UUID()
    let assets: [AssetSummary]
    let startIndex: Int
}
