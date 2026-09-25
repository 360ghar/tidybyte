import SwiftUI

/// One page of the first-run flow.
struct OnboardingPage {
    let systemImage: String
    let tint: Color
    let title: String
    let message: String
}

/// Three-page first-run flow, shown once per install before the app asks for
/// library access.
///
/// The last page is the permission primer. iOS shows the system permission
/// prompt exactly once, and a denial is sticky until the user goes into
/// Settings, so the app spends that one chance only after explaining what the
/// access is for. Previously the prompt fired from an otherwise empty screen.
struct OnboardingView: View {
    /// Called when the user finishes or skips. The caller records the flag and
    /// lets the cover dismiss.
    let onFinish: () -> Void
    /// Runs the system permission prompt. Called only from the final page.
    let onRequestAccess: () async -> Void

    @State private var pageIndex = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pages: [OnboardingPage] = [
        OnboardingPage(
            systemImage: "rectangle.portrait.on.rectangle.portrait.angled",
            tint: .blue,
            title: "Swipe Through Your Library",
            message: "Review one photo at a time. Swipe left to delete, right to keep, or up to file it into an album — and undo anything by mistake."
        ),
        OnboardingPage(
            systemImage: "lock.shield",
            tint: .green,
            title: "Nothing Leaves Your Device",
            message: "TidyByte has no account and no servers. Every scan, comparison, and analysis runs right here on this device."
        ),
        OnboardingPage(
            systemImage: "photo.on.rectangle.angled",
            tint: .orange,
            title: "Access to Your Photos",
            message: "TidyByte reads your library to find duplicates, blurry shots, and oversized files. It only ever changes what you approve. iOS will ask for permission next."
        )
    ]

    private var isLastPage: Bool { pageIndex == Self.pages.count - 1 }

    /// Reduce Motion keeps the page change but drops the slide.
    private var pageAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

    var body: some View {
        VStack(spacing: 0) {
            skipBar

            TabView(selection: $pageIndex) {
                ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, page in
                    pageView(page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(pageAnimation, value: pageIndex)

            footer
        }
        .background(Color.appBackground)
    }

    // MARK: - Skip

    private var skipBar: some View {
        HStack {
            Spacer()
            Button("Skip") {
                HapticHelper.impact(.light)
                onFinish()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityHint("Skips the introduction and asks for photo access later")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
    }

    // MARK: - Page

    private func pageView(_ page: OnboardingPage) -> some View {
        // Scrolls at large text sizes instead of pushing text off screen;
        // centered when it fits.
        GeometryReader { proxy in
            ScrollView {
                pageContent(page)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
            }
        }
    }

    private func pageContent(_ page: OnboardingPage) -> some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: page.systemImage)
                .scaledGlyph(ScaledSize.stateGlyph, weight: .light)
                .foregroundStyle(page.tint)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.md) {
                Text(page.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(page.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.xl)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .readableWidth()
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Spacing.lg) {
            HStack(spacing: Spacing.sm) {
                ForEach(Self.pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == pageIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: index == pageIndex ? 20 : 8, height: 8)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Page \(pageIndex + 1) of \(Self.pages.count)")

            Button(action: advance) {
                Text(isLastPage ? "Allow Access" : "Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(Spacing.lg)
                    .background(.tint)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            .scaleOnPress()
            // The permission gate behind this cover renders its own
            // "Allow Access" button, so UI tests scope to this one by id.
            .accessibilityIdentifier("onboardingPrimaryButton")
            .accessibilityHint(isLastPage
                               ? "Opens the iOS permission prompt for your photo library"
                               : "Shows the next page")
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.bottom, Spacing.xxl)
        .readableWidth(560)
    }

    private func advance() {
        HapticHelper.impact(.light)
        guard isLastPage else {
            withAnimation(pageAnimation) {
                pageIndex += 1
            }
            return
        }
        Task { @MainActor in
            // Ask first, finish second: the cover stays up behind the system
            // alert, so the user isn't dropped into an unexplained screen
            // mid-prompt. The cover then dismisses either way — granted lands in
            // the app, denied lands on the actionable permission screen.
            //
            // `advance()` is not main-actor-isolated, so a bare `Task {}` here
            // would not inherit the main actor, yet `onFinish()` records the
            // `@AppStorage` completion flag.
            await onRequestAccess()
            onFinish()
        }
    }
}
