import SwiftUI
import UIKit

/// Accent for a transient banner. Only the icon and the action pill take the
/// tint; the surface stays neutral so a success never becomes a green slab.
enum ToastStyle {
    case info
    case success
    case warning

    var tint: Color {
        switch self {
        case .info: return .accentColor
        case .success: return .success
        case .warning: return .warning
        }
    }
}

/// Content for a transient banner.
///
/// `Identifiable` rather than plain `String` so re-showing the same text
/// restarts the presenter's auto-dismiss timer instead of being treated as "no
/// change" and dismissed mid-read.
struct ToastMessage: Equatable, Identifiable {
    let id: UUID
    let text: String
    var systemImage: String?
    var style: ToastStyle
    /// Optional action, e.g. "Undo" on a pending delete. When present the
    /// banner stays tappable for that button and is not dismissable by tapping
    /// the body.
    var actionTitle: String?
    var action: (() -> Void)?

    init(
        text: String,
        systemImage: String? = nil,
        style: ToastStyle = .info,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.systemImage = systemImage
        self.style = style
        self.actionTitle = actionTitle
        self.action = action
    }

    /// Confirmation of a completed action. Defaults the icon so call sites
    /// only name the text.
    static func success(text: String, systemImage: String = "checkmark.circle.fill") -> ToastMessage {
        ToastMessage(text: text, systemImage: systemImage, style: .success)
    }

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

/// Transient banner pinned to the top of a screen.
///
/// Shared so every transient message in the app looks and behaves the same:
/// same padding, same surface, same fade/slide, same dismissal.
///
/// The surface is an **opaque, adaptive card**, not a translucent black pill.
/// The old 85%-black capsule had no border and no shadow, so over the black
/// swipe deck, or in dark mode, it dissolved into the background and left the
/// text apparently floating in mid-air — which reads as a rendering bug rather
/// than as a message. It is also dismissable three ways: the close button, a
/// tap on the body, and an upward drag.
struct ToastBanner: View {
    let message: ToastMessage
    var onDismiss: (() -> Void)?

    /// Increase Contrast thickens the border so the card keeps its edge over a
    /// busy photo grid.
    @Environment(\.colorSchemeContrast) private var contrast

    /// Body taps are off when an action is present: the tap would race the
    /// button, and dismissing the banner is the one thing the user did not ask
    /// for when reaching for Undo.
    private var isBodyTappable: Bool {
        onDismiss != nil && message.actionTitle == nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: message.systemImage ?? "info.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(message.style.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(message.text)
                    .font(.footnote.weight(.medium))
                    // Wrap rather than shrink: a squeezed 11pt line is worse
                    // than a second line.
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle = message.actionTitle, let action = message.action {
                    Button {
                        HapticHelper.impact(.light)
                        action()
                    } label: {
                        Text(actionTitle)
                            .font(.footnote.bold())
                            .foregroundStyle(message.style.tint)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.xs)
                            .background(message.style.tint.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            if let onDismiss {
                Button {
                    HapticHelper.impact(.light)
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        // 44pt hit target from a 20pt glyph without spending
                        // 44pt of layout: the expanded content shape is what
                        // taps and VoiceOver actually hit. The 12pt expansion
                        // lands exactly in the row's 12pt gap.
                        .contentShape(Rectangle().inset(by: -12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                .fill(ToastBanner.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                        .strokeBorder(Color.cardBorder, lineWidth: contrast == .increased ? 1.5 : 1)
                }
        }
        .cardShadow()
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous))
        .onTapGesture {
            guard isBodyTappable else { return }
            HapticHelper.impact(.light)
            onDismiss?()
        }
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    // Upward flick only: a downward drag under the thumb would
                    // fight a list scroll if the banner ever sits in-flow.
                    guard let onDismiss, value.translation.height < -20 else { return }
                    HapticHelper.impact(.light)
                    onDismiss()
                }
        )
        .accessibilityAction(named: Text("Dismiss")) { onDismiss?() }
    }

    /// Opaque in both appearances, and lifted off `systemBackground` in each:
    /// `secondarySystemBackground` in light mode, `tertiarySystemBackground`
    /// in dark. A white card on a white list would be a border and a shadow
    /// with nothing to fill them.
    private static var surface: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.tertiarySystemBackground
                : UIColor.secondarySystemBackground
        })
    }
}

/// What the auto-dismiss timer is keyed on. A struct rather than a formatted
/// string so the identity is explicit and cannot collide.
private struct ToastTimerKey: Hashable {
    let id: UUID
    let voiceOver: Bool
}

private struct ToastPresenter: ViewModifier {
    @Binding var message: ToastMessage?
    var duration: Duration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    /// An actionable toast holds long enough to reach its button, and so does
    /// any toast while VoiceOver is on — the user has to navigate to it to
    /// dismiss it, which takes longer than reading it.
    private var visibleDuration: Duration {
        message?.actionTitle != nil || voiceOverEnabled ? max(duration, .seconds(8)) : duration
    }

    /// Reduce Motion keeps the appearance change but drops the travel, matching
    /// how the rest of the app treats `reduceMotionAware` animations.
    private var presentation: Animation {
        reduceMotion ? .easeOut(duration: 0.01) : .spring(response: 0.35, dampingFraction: 0.85)
    }

    private func dismiss() {
        withAnimation(presentation) {
            message = nil
        }
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    ToastBanner(message: message, onDismiss: dismiss)
                        .frame(maxWidth: 560)
                        .padding(.top, Spacing.sm)
                        .padding(.horizontal, Spacing.lg)
                        // Reachable for VoiceOver in every case: it now always
                        // carries a Dismiss button, and hiding it would leave a
                        // visible control no VoiceOver user can focus. The text
                        // is still announced below, so a user who does not
                        // navigate to it does not miss the message.
                        .accessibilityElement(children: .contain)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        // Keyed on the message id and the VoiceOver state: a
                        // new message restarts the timer, and a mid-toast
                        // VoiceOver toggle restarts it with the longer
                        // duration instead of keeping the remainder.
                        .task(id: ToastTimerKey(id: message.id, voiceOver: voiceOverEnabled)) {
                            try? await Task.sleep(for: visibleDuration)
                            guard !Task.isCancelled else { return }
                            dismiss()
                        }
                }
            }
            .animation(presentation, value: message)
            .onChange(of: message?.id) { _, newValue in
                // A transient overlay is easy to miss with VoiceOver unless it
                // is announced.
                guard newValue != nil, let message else { return }
                let spoken = message.actionTitle.map { L10n.format("%@. %@ available.", message.text, $0) } ?? message.text
                UIAccessibility.post(notification: .announcement, argument: spoken)
            }
    }
}

extension View {
    /// Presents `message` as a top-pinned banner, clearing the binding after
    /// `duration`. Owns the show/sleep/hide dance so call sites don't each
    /// re-implement it.
    func toast(_ message: Binding<ToastMessage?>, duration: Duration = .seconds(4)) -> some View {
        modifier(ToastPresenter(message: message, duration: duration))
    }
}
