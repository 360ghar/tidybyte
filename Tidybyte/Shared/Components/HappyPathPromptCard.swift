import SwiftUI
import StoreKit
import UIKit
import MessageUI

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

    /// True when iOS can actually send mail. A `mailto:` `openURL` reports
    /// success whenever Mail is installed — even with no account configured —
    /// and the compose sheet then errors inside Mail with our own sheet already
    /// dismissed. MessageUI answers the real question.
    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    /// The message body: the caller's `prompt` block, then diagnostics.
    static func body(prompt: String) -> String {
        "\(prompt)\n\n---\nThe info below helps us debug — please keep it.\n\(diagnostics)"
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

/// Subject + body for the in-app feedback composer. `Identifiable` so it can
/// drive `sheet(item:)`.
struct MailDraft: Identifiable {
    let id = UUID()
    let subject: String
    let body: String
}

/// The system mail composer, embedded in a SwiftUI sheet.
///
/// Preferred over `openURL(mailto:)` because MessageUI reports the no-account
/// case up front (`FeedbackMail.canSend`), so the caller can keep its sheet open
/// and show the plain-text address instead of handing the user a dead composer.
struct MailComposeView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    /// Called once the composer finishes. SwiftUI owns the presentation, so the
    /// controller is not dismissed directly — the owner clears its presentation
    /// state here. The result is passed through: `.failed` means the message was
    /// neither saved nor queued, so the caller must not treat the feedback as
    /// sent.
    let onFinish: (MFMailComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([FeedbackMail.address])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: (MFMailComposeResult) -> Void

        init(onFinish: @escaping (MFMailComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish(error == nil ? result : .failed)
        }
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
    /// The last composer attempt failed to hand the message to Mail, so the
    /// feedback step shows a retry instead of acting as if it was sent.
    @State private var mailSendFailed = false
    /// The in-app composer's payload, or nil when it is not presented.
    @State private var mailDraft: MailDraft?
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
        .sheet(item: $mailDraft) { draft in
            MailComposeView(subject: draft.subject, body: draft.body) { result in
                mailDraft = nil
                // MessageUI's `.failed` means the message was neither saved nor
                // queued, so the feedback never went out. Keep the prompt open
                // with a retry instead of closing over the loss.
                mailSendFailed = (result == .failed)
                if result != .failed { onClose() }
            }
        }
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

    /// What the feedback step explains: the failure from the last attempt wins,
    /// then the no-account fallback, then the plain ask.
    private var feedbackDetail: String {
        if mailSendFailed {
            return "The message couldn't be sent. Try again, or email us at \(FeedbackMail.address)."
        }
        if mailUnavailable {
            return "No mail account is set up on this device. Email us at \(FeedbackMail.address)."
        }
        return "Tell us what got in the way."
    }

    private var feedback: some View {
        Group {
            heading("What should we fix?", detail: feedbackDetail)
            choiceRow(
                secondary: ("Not now", onClose),
                primary: (mailSendFailed ? "Try Again" : "Send Feedback", sendFeedback)
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
        // MessageUI reports the no-account case up front, so the sheet stays
        // open with the plain-text address instead of closing into a dead Mail
        // composer — which is what `openURL(mailto:)` used to do, because it
        // reports success whenever Mail is merely installed.
        guard FeedbackMail.canSend else {
            mailUnavailable = true
            return
        }
        mailSendFailed = false
        mailDraft = MailDraft(
            subject: "TidyByte Feedback",
            body: FeedbackMail.body(prompt: "What got in the way:\n\nWhat would make TidyByte better:\n")
        )
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
