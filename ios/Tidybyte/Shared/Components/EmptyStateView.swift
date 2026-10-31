import SwiftUI

struct EmptyStateView: View {
    let icon: String
    /// `LocalizedStringKey`, not `String`.
    ///
    /// This is the difference between a translated screen and an English one.
    /// A `String` parameter receives the literal as plain text and never looks
    /// it up; a `LocalizedStringKey` resolves against the environment locale at
    /// render time, so every call site that passes a literal — or a ternary of
    /// literals — localizes with no change at the call site.
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var iconColor: Color = .secondary
    var actionTitle: LocalizedStringKey?
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
    /// The label is an app-owned caption, so it localizes.
    let label: LocalizedStringKey
    /// The value is data — a date, a size, a resolution — already formatted for
    /// the user. Rendering it verbatim is deliberate: a value that happens to
    /// equal a catalog key (a size of "1 MB", a resolution of "1080p") must not
    /// be swapped for a translation.
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value)
                .font(.caption.bold())
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Shared "no more items" empty state for full-screen media previews.
/// `title` differs per tool ("No more items" vs "No more Live Photos").
struct PreviewEmptyState: View {
    let title: LocalizedStringKey
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
