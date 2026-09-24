import SwiftUI
import StoreKit
import UIKit

/// App Store routes shared by the happy-path prompt and Settings.
/// The web URL is region-neutral (`/app/id…` redirects to the user's own
/// storefront, unlike `/in/app/…` which pins India).
enum AppStoreLinks {
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6775769763")!

    /// Write-review deep link. Used for explicit taps because unlike the
    /// OS-throttled `requestReview` API (max 3 prompts / 365 days, silently
    /// suppressed when exhausted), a deliberate "Rate" tap must always land
    /// on the review form.
    static let writeReviewURL = URL(string: "itms-apps://itunes.apple.com/app/id6775769763?action=write-review")!

    /// Pre-filled share message. `statLine` is what the user accomplished,
    /// e.g. "removed 24 duplicates"; `nil` falls back to generic copy.
    static func shareMessage(statLine: String?) -> String {
        let deed = statLine.map { "I just \($0)" } ?? "I'm cleaning up my photo library"
        return "\(deed) with TidyByte — a private, on-device photo cleanup app. \(appStoreURL.absoluteString)"
    }
}

/// Feedback email shared by Settings and the prompt's "Not really" path.
@MainActor
enum FeedbackMail {
    static let address = "contact@sakshammittal.com"

    /// `prompt` is the question block the user fills in; diagnostics follow it.
    static func url(subject: String, prompt: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: "\(prompt)\n\n---\nThe info below helps us debug — please keep it.\n\(diagnostics)")
        ]
        return components.url
    }

    private static var diagnostics: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return """
        App: TidyByte \(version) (\(build))
        iOS: \(UIDevice.current.systemVersion)
        Device: \(deviceModelIdentifier)
        """
    }

    private static var deviceModelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let id = mirror.children.reduce(into: "") { result, element in
            if let value = element.value as? Int8, value != 0 {
                result.append(Character(UnicodeScalar(UInt8(value))))
            }
        }
        return id.isEmpty ? UIDevice.current.model : id
    }
}

/// Two-step "Enjoying TidyByte?" prompt, presented in a sheet after a
/// milestone success. "Yes" asks for a rating (Apple's in-app sheet, with a
/// write-review link in case iOS suppresses it); "Not really" asks for
/// feedback instead, so an unhappy user is heard rather than sent to the store.
struct HappyPathPromptCard: View {
    /// What the user just accomplished, e.g. "removed 24 duplicates". `nil`
    /// hides the line and uses generic share copy.
    var statLine: String?
    var onClose: () -> Void

    private enum Step { case question, rated, feedback }

    @State private var step: Step = .question
    @State private var mailUnavailable = false
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Spacing.lg) {
            switch step {
            case .question: question
            case .rated: rated
            case .feedback: feedback
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.reduceMotionAware(.spring(response: 0.35, dampingFraction: 0.9), reduceMotion: reduceMotion), value: step)
    }

    // MARK: - Steps

    private var question: some View {
        Group {
            heading("Enjoying TidyByte?", detail: statLine.map { "You just \($0)." })
            choiceRow(
                secondary: ("Not really", { step = .feedback }),
                primary: ("Yes", answerYes)
            )
        }
    }

    private var rated: some View {
        Group {
            heading("Thanks for the support", detail: "Your rating helps other people find TidyByte.")
            choiceButton("Done", prominent: true, action: onClose)
            // Fallback: iOS may suppress the rating sheet with no signal.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.xl) { secondaryLinks }
                VStack(spacing: Spacing.xs) { secondaryLinks }
            }
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Text-only so both links share one baseline.
    @ViewBuilder
    private var secondaryLinks: some View {
        Button("Rate on the App Store") {
            openURL(AppStoreLinks.writeReviewURL)
            onClose()
        }
        .frame(minHeight: 44)
        ShareLink(item: AppStoreLinks.shareMessage(statLine: statLine)) {
            Text("Share TidyByte")
        }
        .frame(minHeight: 44)
    }

    private var feedback: some View {
        Group {
            heading(
                "What should we fix?",
                detail: mailUnavailable
                    ? "No mail account is set up on this device. Email us at \(FeedbackMail.address)."
                    : "Tell us what got in the way."
            )
            choiceRow(
                secondary: ("Not now", onClose),
                primary: ("Send Feedback", sendFeedback)
            )
        }
    }

    // MARK: - Actions

    private func answerYes() {
        HapticHelper.impact(.light)
        AppPreferences.saveHasRatedApp()
        step = .rated
        requestReview()
    }

    private func sendFeedback() {
        guard let url = FeedbackMail.url(
            subject: "TidyByte Feedback",
            prompt: "What got in the way:\n\nWhat would make TidyByte better:\n"
        ) else { return }
        openURL(url) { accepted in
            if accepted { onClose() } else { mailUnavailable = true }
        }
    }

    // MARK: - Building Blocks

    private func heading(_ title: String, detail: String?) -> some View {
        VStack(spacing: Spacing.sm) {
            Text(title)
                .font(.title3.bold())
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Two equal-width filled buttons; stacks vertically when the text is too
    /// large to fit side by side.
    private func choiceRow(
        secondary: (title: String, action: () -> Void),
        primary: (title: String, action: () -> Void)
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.md) {
                choiceButton(secondary.title, prominent: false, action: secondary.action)
                choiceButton(primary.title, prominent: true, action: primary.action)
            }
            VStack(spacing: Spacing.md) {
                choiceButton(primary.title, prominent: true, action: primary.action)
                choiceButton(secondary.title, prominent: false, action: secondary.action)
            }
        }
    }

    private func choiceButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    prominent ? Color.accentColor : Color.controlSurface,
                    in: RoundedRectangle(cornerRadius: CornerRadius.large)
                )
                .foregroundStyle(prominent ? Color.white : Color.primary)
        }
        .scaleOnPress()
    }
}
