import SwiftUI

/// Inline, non-modal error row for the cleanup tools.
///
/// Replaces the OK-only `.alert("Error")` pattern. An alert interrupts the task,
/// costs a tap to dismiss, and usually leaves the screen in the same broken
/// state it was already in. The banner stays next to the content it describes
/// and can carry a retry, so recovery is one tap instead of two.
struct ToolErrorBanner: View {
    /// The two kinds of text a banner shows. They need separate types because
    /// they need separate rendering.
    ///
    /// `Text(_ key: LocalizedStringKey)` resolves the string through the String
    /// Catalog **and** parses it as Markdown. That is right for copy this app
    /// owns and translates, and wrong for text that is already final: an error
    /// description or a view-model sentence can contain `*`, `_`, or `[x](y)`
    /// (a file name inside an error message, say), which Markdown would
    /// italicize, strip, or turn into a link. Runtime text goes through
    /// `Text(verbatim:)` instead, which draws the characters as typed.
    enum Source {
        /// A String Catalog key: `Text` resolves it to the shipped translation.
        case key(LocalizedStringKey)
        /// Text that is already in the user's language and must not be looked
        /// up or re-parsed: `error.localizedDescription`, a sentence the view
        /// model built with `L10n`, or a tool name.
        case runtimeText(String)
    }

    var message: Source
    var title: Source = .key("Something went wrong")
    var retryTitle: LocalizedStringKey = "Try Again"
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Color.warning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                text(for: title)
                    .font(.subheadline.bold())

                text(for: message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let onRetry {
                    Button(retryTitle, action: onRetry)
                        .font(.footnote.bold())
                        .padding(.top, Spacing.xs)
                }
            }

            Spacer(minLength: 0)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss error")
            }
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .fill(Color.warning.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .strokeBorder(Color.warning.opacity(0.35), lineWidth: 1)
                }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Draws one `Source`: keys resolve against the catalog, runtime text is
    /// rendered exactly as given.
    private func text(for source: Source) -> Text {
        switch source {
        case .key(let key):
            Text(key)
        case .runtimeText(let string):
            Text(verbatim: string)
        }
    }
}

extension ToolErrorBanner {
    /// Convenience for the common shape: every argument is a catalog key.
    ///
    /// Declared in an extension so the memberwise initializer, which is what
    /// the `.runtimeText` path uses, survives.
    init(
        message: LocalizedStringKey,
        title: LocalizedStringKey = "Something went wrong",
        retryTitle: LocalizedStringKey = "Try Again",
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.init(
            message: .key(message),
            title: .key(title),
            retryTitle: retryTitle,
            onRetry: onRetry,
            onDismiss: onDismiss
        )
    }
}
