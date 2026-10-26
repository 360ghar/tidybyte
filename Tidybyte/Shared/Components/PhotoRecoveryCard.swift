import SwiftUI
import UIKit

/// The empty state for "the library came back empty", shared by the Swipe
/// session and both album pickers.
///
/// Deliberately not `EmptyStateView`: a permission problem needs more than an
/// icon and a line of copy. It needs the recovery steps written out in order,
/// and the actions that fix it — Settings, and for limited access widening the
/// selection. Rendering this as plain sentences is what turned the bug into a
/// support ticket in the first place.
///
/// A retry is only offered where it can help, and it is never the primary: the
/// two limited-access states can be fixed by sharing more photos, and the
/// stuck-permission state by Settings.
struct PhotoRecoveryCard: View {
    let presentation: PhotoRecoveryPresentation
    let onAction: (PhotoRecoveryPresentation.Action) -> Void

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: glyph)
                .scaledGlyph(ScaledSize.stateGlyph)
                .foregroundStyle(Color.warning)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.md) {
                // The presentation holds catalog keys, so these resolve against
                // the live `\.locale` — including if the language changes while
                // the card is up.
                Text(LocalizedStringKey(presentation.title))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)

                Text(LocalizedStringKey(presentation.message))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            if !presentation.steps.isEmpty {
                stepsCard
            }

            actions
        }
        .padding(.horizontal, Spacing.lg)
    }

    private var glyph: String {
        switch presentation.actions.first {
        case .addPhotos: "photo.badge.plus"
        default: "lock.shield"
        }
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(Array(presentation.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: Spacing.md) {
                    // `verbatim`: a step number is not copy. As a plain literal
                    // it would become the catalog key "%lld." and need 20
                    // translations for a number.
                    Text(verbatim: "\(index + 1).")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.secondary)

                    Text(LocalizedStringKey(step))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                // One element per step, spoken as "1. …". As separate elements
                // the marker was hidden and the sentence had no number at all,
                // so VoiceOver read three unordered instructions.
                //
                // The number is verbatim and the sentence is keyed, because
                // `step` is a catalog key: speaking it as plain text would read
                // the English source aloud in every other language.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(index + 1). ") + Text(LocalizedStringKey(step)))
            }
        }
        .glassCard()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(Array(presentation.actions.enumerated()), id: \.offset) { index, action in
                Button {
                    HapticHelper.impact(.light)
                    onAction(action)
                } label: {
                    // `action.title` is a catalog key, so this resolves against
                    // the live `\.locale` — and re-resolves if the language
                    // changes while the card is up.
                    //
                    // The style goes on this Text, not on the Button: a Button
                    // re-tints its label with the accent colour, so an outer
                    // `.foregroundStyle(.white)` lost and the primary label
                    // rendered blue on the blue fill. Same shape as every other
                    // filled button in the app.
                    Text(LocalizedStringKey(action.title))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .modifier(RecoveryActionStyle(isPrimary: index == 0))
                }
                .scaleOnPress()
            }
        }
    }
}

/// Filled for the primary action, tinted outline for the rest. One modifier
/// rather than two button styles so the two can never drift apart.
///
/// Applied to the button's *label*, never to the `Button`: that is the only
/// place a `foregroundStyle` survives the button style's own tint.
private struct RecoveryActionStyle: ViewModifier {
    let isPrimary: Bool

    func body(content: Content) -> some View {
        if isPrimary {
            content
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        } else {
            content
                .foregroundStyle(.blue)
                .background {
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .strokeBorder(.blue.opacity(0.5), lineWidth: 1)
                }
        }
    }
}

// MARK: - Action handling

extension PhotoRecoveryPresentation.Action {
    /// Runs the action, with one implementation shared by every caller so
    /// "Open Settings" and "Add More Photos" can never mean different things on
    /// different screens.
    ///
    /// `.retry` is the caller's job (it owns the load), so it is not handled
    /// here.
    @MainActor
    static func perform(_ action: PhotoRecoveryPresentation.Action) {
        switch action {
        case .addPhotos:
            PhotoPermissionHandler.presentLimitedLibraryPicker()
        case .openSettings:
            PhotoPermissionHandler.openSettings()
        case .retry:
            // Callers intercept this; nothing generic to do.
            break
        }
    }
}
