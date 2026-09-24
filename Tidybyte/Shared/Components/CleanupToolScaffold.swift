import SwiftUI

// MARK: - Shared cleanup tool chrome
//
// The ten cleanup tools each hand-rolled the same three screens: an idle
// explainer, a determinate scan, and a skeleton while fetching. They drifted —
// progress read "42%" in one tool and "42% · 3 issues found" in another, cancel
// was a red pill in one and a grey one in the next, and two tools offered no
// cancel at all. These three views are that chrome, once.
//
// Deliberately NOT unified here: the results view. A grid of screenshots, a list
// of files, and a list of burst groups are genuinely different layouts, and
// forcing one abstraction over them would cost more than the duplication does.

/// The idle / "what does this tool do" screen.
///
/// Used by every tool that needs an explicit start action (the four scanning
/// tools) and by the fetch-first tools while they have nothing to show.
struct ToolIdleView<Options: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    let primaryTitle: String
    let primaryAction: () -> Void
    var primaryHint: String?
    var footnote: String?
    /// Tool-specific controls between the copy and the button, e.g. the
    /// duplicate scan-type picker.
    @ViewBuilder let options: () -> Options

    init(
        icon: String,
        tint: Color,
        title: String,
        message: String,
        primaryTitle: String,
        primaryHint: String? = nil,
        footnote: String? = nil,
        primaryAction: @escaping () -> Void,
        @ViewBuilder options: @escaping () -> Options
    ) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.message = message
        self.primaryTitle = primaryTitle
        self.primaryHint = primaryHint
        self.footnote = footnote
        self.primaryAction = primaryAction
        self.options = options
    }

    var body: some View {
        // Scrolls rather than centering, because at accessibility text sizes the
        // copy plus the button exceed a short screen and the button would
        // otherwise be pushed out of reach.
        ScrollView {
            VStack(spacing: Spacing.xl) {
                Spacer(minLength: Spacing.xxl)

                ToolStateGlyph(icon: icon, tint: tint)

                VStack(spacing: Spacing.sm) {
                    Text(title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                options()

                Button(action: primaryAction) {
                    Text(primaryTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.lg)
                        .background(.tint)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                }
                .scaleOnPress()
                .accessibilityHint(primaryHint ?? "")

                if let footnote {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Spacing.xxl)
            }
            .padding(.horizontal, Spacing.xxl)
            .frame(maxWidth: .infinity)
            .readableWidth()
        }
    }
}

extension ToolIdleView where Options == EmptyView {
    init(
        icon: String,
        tint: Color,
        title: String,
        message: String,
        primaryTitle: String,
        primaryHint: String? = nil,
        footnote: String? = nil,
        primaryAction: @escaping () -> Void
    ) {
        self.init(
            icon: icon,
            tint: tint,
            title: title,
            message: message,
            primaryTitle: primaryTitle,
            primaryHint: primaryHint,
            footnote: footnote,
            primaryAction: primaryAction,
            options: { EmptyView() }
        )
    }
}

/// Determinate scan progress, with a cancel that is always present.
///
/// Every long-running scan gets an explicit way out — the earlier inconsistency
/// (two tools had none) is exactly how users get trapped on a screen with no
/// controls.
struct ToolScanningView: View {
    let icon: String
    let tint: Color
    let title: String
    let progress: Float
    /// Trailing detail after the percentage, e.g. "37 items found". Tools with
    /// nothing to report pass nil and the line is just the percentage.
    var detail: String?
    var cancelTitle: String = "Cancel"
    let onCancel: () -> Void

    private var progressLabel: String {
        let percent = "\(Int(progress * 100))%"
        guard let detail, !detail.isEmpty else { return percent }
        return "\(percent) \u{00B7} \(detail)"
    }

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Bare glyph, no glow halo behind it.
            Image(systemName: icon)
                .scaledGlyph(ScaledSize.stateGlyph / 2, weight: .light)
                .foregroundStyle(tint.opacity(0.8))
                .symbolEffect(.pulse)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.md) {
                Text(title)
                    .font(.headline)

                ProgressView(value: progress)
                    .tint(tint)

                Text(progressLabel)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            }
            .glassCard()
            .padding(.horizontal, Spacing.lg)
            .readableWidth()

            // Live region so VoiceOver reports progress without the user having
            // to hunt for the changed value.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
            .accessibilityValue(progressLabel)

            Button(role: .destructive, action: onCancel) {
                Text(cancelTitle)
                    .font(.headline)
                    .padding(.horizontal, Spacing.xxxl)
                    .padding(.vertical, Spacing.md)
                    .background(Color.destructive.opacity(0.12))
                    .foregroundStyle(Color.destructive)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            .scaleOnPress()

            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
    }
}

/// Indeterminate skeleton while the initial fetch runs.
///
/// `onCancel` is optional because cancellation is a property of the view model,
/// not of the screen: a tool whose fetch runs inside a `ScanRunner` can be
/// stopped, and one whose fetch is a single awaited call cannot. Passing nil
/// omits the button rather than showing one that does nothing.
struct ToolLoadingView<Skeleton: View>: View {
    var cancelTitle: String = "Cancel"
    var onCancel: (() -> Void)?
    @ViewBuilder let skeleton: () -> Skeleton

    init(
        cancelTitle: String = "Cancel",
        onCancel: (() -> Void)? = nil,
        @ViewBuilder skeleton: @escaping () -> Skeleton
    ) {
        self.cancelTitle = cancelTitle
        self.onCancel = onCancel
        self.skeleton = skeleton
    }

    var body: some View {
        skeleton()
            .overlay(alignment: .bottom) {
                if let onCancel {
                    Button(action: onCancel) {
                        Text(cancelTitle)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                    .scaleOnPress()
                    .padding(.bottom, Spacing.lg)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Loading")
    }
}

/// The skeleton list shared by the row-backed tools (bursts, large files, live
/// photos, both compression flows) — four byte-identical copies before this.
struct ToolSkeletonList: View {
    var rows: Int = 6

    var body: some View {
        List {
            ForEach(0..<rows, id: \.self) { _ in
                SkeletonRow()
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }
}

/// The bare-glyph motif shared by the idle and empty states.
///
/// A single SF Symbol with no halo or bloom, so the glyph alone carries the
/// meaning at loading and empty sizes.
struct ToolStateGlyph: View {
    let icon: String
    let tint: Color

    var body: some View {
        // Bare glyph: no glow halo, no bloom shadow.
        Image(systemName: icon)
            .scaledGlyph(ScaledSize.stateGlyph, weight: .light)
            .foregroundStyle(tint.opacity(0.8))
            .accessibilityHidden(true)
    }
}
