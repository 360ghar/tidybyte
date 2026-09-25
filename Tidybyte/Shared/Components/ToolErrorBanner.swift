import SwiftUI

/// Inline, non-modal error row for the cleanup tools.
///
/// Replaces the OK-only `.alert("Error")` pattern. An alert interrupts the task,
/// costs a tap to dismiss, and usually leaves the screen in the same broken
/// state it was already in. The banner stays next to the content it describes
/// and can carry a retry, so recovery is one tap instead of two.
struct ToolErrorBanner: View {
    let message: String
    var title: String = "Something went wrong"
    var retryTitle: String = "Try Again"
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Color.warning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.subheadline.bold())

                Text(message)
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
}
