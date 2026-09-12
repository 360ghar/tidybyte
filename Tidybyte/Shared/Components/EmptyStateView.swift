import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var iconColor: Color = .secondary
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.xl) {
            // The halo/glyph pair is shared with the cleanup tool states so the
            // motif stays identical, and so its Dynamic Type scaling is defined
            // in exactly one place.
            ToolStateGlyph(icon: icon, tint: iconColor)

            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(.title2.bold())

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxxl)
            }
            .accessibilityElement(children: .combine)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .padding(.horizontal, Spacing.xxxl)
                        .padding(.vertical, Spacing.md)
                        .background(.tint)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                }
                .scaleOnPress()
            }
        }
        .fadeSlideIn()
    }
}

/// Shared label/value metadata row used by the duplicate and similar
/// comparison screens (previously a private `metadataRow` duplicated in both).
struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Shared "no more items" empty state for full-screen media previews.
/// `title` differs per tool ("No more items" vs "No more Live Photos").
struct PreviewEmptyState: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Spacing.md) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }
}
