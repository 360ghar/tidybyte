import SwiftUI
import UIKit

/// Content for a transient banner.
///
/// `Identifiable` rather than plain `String` so re-showing the same text
/// restarts the presenter's auto-dismiss timer instead of being treated as "no
/// change" and dismissed mid-read.
struct ToastMessage: Equatable, Identifiable {
    let id: UUID
    let text: String
    var systemImage: String?
    /// Optional trailing action, e.g. "Open Photos" on a post-delete
    /// confirmation. When present the banner stays tappable; when absent it is
    /// hidden from VoiceOver because the presenter announces the text instead.
    var actionTitle: String?
    var action: (() -> Void)?

    init(text: String, systemImage: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.id = UUID()
        self.text = text
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

/// Transient banner pinned to the top of a screen.
///
/// Shared so every transient message in the app looks and behaves the same:
/// same padding, same surface, same fade/slide, same dismissal. Previously the
/// swipe session carried two hand-rolled variants of this view.
struct ToastBanner: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if let systemImage = message.systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }

            Text(message.text)
                .font(.footnote.weight(.medium))
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle = message.actionTitle, let action = message.action {
                Button(actionTitle, action: action)
                    .font(.footnote.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Capsule().fill(Color.black.opacity(0.85)))
        .accessibilityElement(children: .combine)
    }
}

private struct ToastPresenter: ViewModifier {
    @Binding var message: ToastMessage?
    var duration: Duration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    /// With VoiceOver an actionable toast stays long enough to reach its
    /// button.
    private var visibleDuration: Duration {
        voiceOverEnabled && message?.actionTitle != nil ? max(duration, .seconds(8)) : duration
    }

    /// Reduce Motion keeps the appearance change but drops the travel, matching
    /// how the rest of the app treats `reduceMotionAware` animations.
    private var presentation: Animation {
        reduceMotion ? .easeOut(duration: 0.01) : .spring(response: 0.35, dampingFraction: 0.85)
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    ToastBanner(message: message)
                        .padding(.top, Spacing.sm)
                        .padding(.horizontal, Spacing.lg)
                        // Text-only toasts are announced below; a toast with an
                        // action must stay reachable so it isn't hidden.
                        .accessibilityHidden(message.actionTitle == nil)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: message.id) {
                            try? await Task.sleep(for: visibleDuration)
                            guard !Task.isCancelled else { return }
                            withAnimation(presentation) {
                                self.message = nil
                            }
                        }
                }
            }
            .animation(presentation, value: message)
            .onChange(of: message?.id) { _, newValue in
                // A transient overlay is easy to miss with VoiceOver unless it
                // is announced; only announce text-only toasts, since an
                // actionable one is reachable by focus.
                // Actionable toasts are announced too, naming the action.
                guard newValue != nil, let message else { return }
                let spoken = message.actionTitle.map { "\(message.text). \($0) available." } ?? message.text
                UIAccessibility.post(notification: .announcement, argument: spoken)
            }
    }
}

extension View {
    /// Presents `message` as a top-pinned banner, clearing the binding after
    /// `duration`. Owns the show/sleep/hide dance so call sites don't each
    /// re-implement it.
    func toast(_ message: Binding<ToastMessage?>, duration: Duration = .seconds(2.5)) -> some View {
        modifier(ToastPresenter(message: message, duration: duration))
    }
}
