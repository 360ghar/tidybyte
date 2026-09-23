import SwiftUI
import StoreKit

/// Presents the happy-path rate/share card as a transient bottom banner for
/// cleanup tools that have no completion screen (their only success signal
/// today is a haptic). Non-blocking: never intercepts navigation, auto-
/// dismisses after 6 seconds, and sits inside the safe area so it never
/// collides with the home indicator.
struct HappyPathCelebrationModifier: ViewModifier {
    @Binding var isPresented: Bool
    var statLine: String?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let autoDismissSeconds: UInt64 = 6

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isPresented {
                    HappyPathPromptCard(statLine: statLine)
                        .overlay(alignment: .topTrailing) {
                            // With VoiceOver the card stays until closed: six
                            // seconds is not enough to reach its buttons.
                            if voiceOverEnabled {
                                Button {
                                    isPresented = false
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                        .frame(minWidth: 44, minHeight: 44)
                                }
                                .accessibilityLabel("Close")
                            }
                        }
                        .readableWidth(560)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, Spacing.xl)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        // Re-run when VoiceOver turns off, so the timer starts.
                        .task(id: voiceOverEnabled) {
                            // `.task` lives on the conditionally-inserted view,
                            // so setting `isPresented = false` below removes
                            // the view and cancels the sleep — no leak, and a
                            // re-trigger restarts the timer.
                            guard !voiceOverEnabled else { return }
                            try? await Task.sleep(nanoseconds: Self.autoDismissSeconds * 1_000_000_000)
                            isPresented = false
                        }
                }
            }
            .animation(.reduceMotionAware(.spring(response: 0.4, dampingFraction: 0.85), reduceMotion: reduceMotion), value: isPresented)
    }
}

extension View {
    /// - Parameter statLine: what the user accomplished, e.g. "removed 24
    ///   duplicates"; feeds the card's share message. `nil` uses generic copy.
    func happyPathCelebration(isPresented: Binding<Bool>, statLine: String? = nil) -> some View {
        modifier(HappyPathCelebrationModifier(isPresented: isPresented, statLine: statLine))
    }
}

/// One-line happy-path trigger shared by all cleanup tools: success haptic,
/// celebration banner, and milestone-gated native review prompt.
@MainActor
enum HappyPathReporter {
    /// Fires haptic + banner + milestone review. Use when the banner's
    /// `statLine` is computed live in the modifier (e.g. from `viewModel.deletedCount`).
    static func fire(
        isCelebrating: Binding<Bool>,
        requestReview: RequestReviewAction
    ) {
        HapticHelper.notification(.success)
        isCelebrating.wrappedValue = true
        if AppPreferences.recordSuccessfulAction() {
            requestReview()
            AppPreferences.recordReviewPromptDate()
        }
    }

    /// Fires haptic + banner + milestone review and sets the banner's stat
    /// line. Use when the view holds a `celebrationStatLine` state var.
    static func fire(
        isCelebrating: Binding<Bool>,
        statLine: Binding<String?>,
        line: String,
        requestReview: RequestReviewAction
    ) {
        statLine.wrappedValue = line
        fire(isCelebrating: isCelebrating, requestReview: requestReview)
    }
}
