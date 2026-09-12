import SwiftUI

/// App Store routes shared by the happy-path celebration card and Settings.
/// The web URL is region-neutral (`/app/id…` redirects to the user's own
/// storefront, unlike `/in/app/…` which pins India).
enum AppStoreLinks {
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6775769763")!

    /// Write-review deep link. Used for explicit taps because unlike the
    /// OS-throttled `requestReview` API (max 3 prompts / 365 days, silently
    /// suppressed when exhausted), a deliberate "Rate Us" tap must always land
    /// on the review form.
    static let writeReviewURL = URL(string: "itms-apps://itunes.apple.com/app/id6775769763?action=write-review")!

    /// Pre-filled share message. `statLine` is what the user accomplished,
    /// e.g. "removed 24 duplicates"; `nil` falls back to generic copy.
    static func shareMessage(statLine: String?) -> String {
        let deed = statLine.map { "I just \($0)" } ?? "I'm cleaning up my photo library"
        return "\(deed) with TidyByte — a private, on-device photo cleanup app. \(appStoreURL.absoluteString)"
    }
}

/// "Enjoying TidyByte?" card shown after a happy-path success (or permanently
/// on the swipe completion screen). Offers two user-initiated actions:
/// Rate (App Store review form) and Share (pre-filled message + store link).
struct HappyPathPromptCard: View {
    /// What the user just accomplished, e.g. "removed 24 duplicates" — baked
    /// into the share message so friends see a real result, not an ad. `nil`
    /// falls back to generic copy (Settings row, sessions without deletions).
    var statLine: String?

    @Environment(\.openURL) private var openURL

    private var shareMessage: String {
        AppStoreLinks.shareMessage(statLine: statLine)
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            Text("Enjoying TidyByte?")
                .font(.headline)

            Text("A quick rating helps other people clean up their libraries too.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: Spacing.md) {
                Button {
                    HapticHelper.impact(.light)
                    openURL(AppStoreLinks.writeReviewURL)
                } label: {
                    Label("Rate Us", systemImage: "star.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(.blue.gradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                }
                .scaleOnPress()

                ShareLink(item: shareMessage) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(Color.cardSurface)
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                        .overlay {
                            RoundedRectangle(cornerRadius: CornerRadius.medium)
                                .strokeBorder(Color.cardBorder, lineWidth: 1)
                        }
                }
                .scaleOnPress()
            }
        }
        .glassCard()
    }
}
