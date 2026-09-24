import SwiftUI

/// Presents the "Enjoying TidyByte?" prompt in a compact sheet after a
/// milestone success. A sheet, not an overlay: its opaque surface and dimmed
/// backdrop keep the grid below from showing through, and it brings
/// swipe-to-dismiss and VoiceOver focus for free. No auto-dismiss — the
/// prompt is a two-step question and the user decides when it goes.
struct HappyPathCelebrationModifier: ViewModifier {
    @Binding var isPresented: Bool
    var statLine: String?

    @State private var showsPrompt = false
    /// Measured from the content so the sheet hugs it at every Dynamic Type size.
    @State private var promptHeight: CGFloat = 260

    /// Lets the delete alert finish dismissing and the updated list settle
    /// before the sheet rises over it.
    private static let presentationDelay: Duration = .milliseconds(600)

    func body(content: Content) -> some View {
        content
            .task(id: isPresented) {
                guard isPresented else { return }
                try? await Task.sleep(for: Self.presentationDelay)
                // Left the screen during the delay: drop the request so the
                // next milestone can re-trigger it.
                guard !Task.isCancelled else {
                    isPresented = false
                    return
                }
                showsPrompt = true
            }
            .sheet(isPresented: $showsPrompt, onDismiss: { isPresented = false }) {
                // Scrolls only when the largest text sizes outgrow the screen.
                ScrollView {
                    HappyPathPromptCard(statLine: statLine) { showsPrompt = false }
                        .padding(.horizontal, Spacing.xl)
                        .padding(.top, Spacing.xxxl)
                        .padding(.bottom, Spacing.lg)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { promptHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .presentationDetents([.height(promptHeight)])
                .presentationDragIndicator(.visible)
                // Opaque on purpose: iOS 26 renders a compact sheet as
                // Liquid Glass, which lets the screen below bleed through.
                .presentationBackground(Color(.systemBackground))
                .fittedPresentationSizing()
                // Recorded on presentation, not on the answer, so a
                // swipe-down still consumes the cooldown.
                .onAppear { AppPreferences.recordReviewPromptDate() }
            }
    }
}

private extension View {
    /// iPad presents sheets as a large form sheet that ignores height detents;
    /// `.fitted` sizes it to the content instead. iPhone is unaffected.
    @ViewBuilder
    func fittedPresentationSizing() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.fitted)
        } else {
            self
        }
    }
}

extension View {
    /// - Parameter statLine: what the user accomplished, e.g. "removed 24
    ///   duplicates"; shown in the prompt and fed to its share message.
    func happyPathCelebration(isPresented: Binding<Bool>, statLine: String? = nil) -> some View {
        modifier(HappyPathCelebrationModifier(isPresented: isPresented, statLine: statLine))
    }
}

/// One-line happy-path trigger shared by all cleanup tools: success haptic on
/// every success, and the rating prompt only when the milestone gate passes.
@MainActor
enum HappyPathReporter {
    /// Fires the haptic and, on a milestone, the prompt. Use when the prompt's
    /// `statLine` is computed live in the modifier (e.g. from `viewModel.deletedCount`).
    static func fire(isCelebrating: Binding<Bool>) {
        HapticHelper.notification(.success)
        recordSuccess(presenting: isCelebrating)
    }

    /// Fires the haptic and, on a milestone, the prompt with this stat line.
    /// Use when the view holds a `celebrationStatLine` state var.
    static func fire(
        isCelebrating: Binding<Bool>,
        statLine: Binding<String?>,
        line: String
    ) {
        statLine.wrappedValue = line
        fire(isCelebrating: isCelebrating)
    }

    /// Counts one success and presents the prompt when it is due. No haptic,
    /// for screens that already played their own.
    static func recordSuccess(presenting isCelebrating: Binding<Bool>) {
        if AppPreferences.recordSuccessfulAction() {
            isCelebrating.wrappedValue = true
        }
    }
}
