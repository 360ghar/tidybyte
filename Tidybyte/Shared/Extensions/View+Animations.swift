import SwiftUI

// MARK: - Fade Slide In

/// Entrance motion for rows and cards. Content is ALWAYS fully visible: only
/// the vertical offset animates, so a row whose animation never runs (a
/// backgrounded tab, a screenshot pass, a lazy row scrolled into view late)
/// still shows. The delay is capped: callers pass `index * 0.03`, and an
/// uncapped delay left row 500 of a long list waiting 15 s.
struct FadeSlideInModifier: ViewModifier {
    let delay: Double
    @State private var isSettled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let maxDelay: Double = 0.3

    func body(content: Content) -> some View {
        content
            .offset(y: isSettled || reduceMotion ? 0 : 12)
            .onAppear {
                guard !isSettled else { return }
                if reduceMotion {
                    isSettled = true
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85).delay(min(delay, Self.maxDelay))) {
                        isSettled = true
                    }
                }
            }
    }
}

extension View {
    func fadeSlideIn(delay: Double = 0) -> some View {
        modifier(FadeSlideInModifier(delay: delay))
    }
}

// MARK: - Scale On Press Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension View {
    func scaleOnPress() -> some View {
        self.buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Reduce Motion

extension Animation {
    /// Returns `base`, or a near-instant animation when Reduce Motion is enabled,
    /// so large motion (card flings, spring scaling) is calmed for users who need it.
    static func reduceMotionAware(_ base: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.01) : base
    }
}

// MARK: - State Transition

extension AnyTransition {
    static var stateTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.95)).animation(.spring(response: 0.35, dampingFraction: 0.85))
    }
}

// MARK: - Animated Counter

struct AnimatedNumberModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.contentTransition(.numericText())
    }
}

extension View {
    func animatedNumber() -> some View {
        modifier(AnimatedNumberModifier())
    }
}

// MARK: - Pull to Refresh

extension View {
    /// App-wide pull-to-refresh: native `.refreshable` plus a subtle completion haptic,
    /// so every screen behaves identically. Attach to the screen's `List`/`ScrollView`/`Form`.
    ///
    /// The `action` should re-fetch data WITHOUT toggling a full-screen loading/skeleton
    /// state, so existing content stays visible under the system refresh spinner.
    ///
    /// The action is `@MainActor`-isolated (which is also implicitly `Sendable`, so SwiftUI's
    /// `refreshable` still accepts it). This lets call sites touch main-actor state — a
    /// `@State` property, a SwiftData `ModelContext`, a `@MainActor` view model — without
    /// the "cannot exit main actor-isolated context" / "Sendable closure" warnings that a
    /// plain `@Sendable` action would trigger.
    func pullToRefresh(_ action: @escaping @MainActor () async -> Void) -> some View {
        refreshable {
            await action()
            // `.refreshable`'s own closure is non-isolated; hop to the main actor for the haptic.
            await MainActor.run { HapticHelper.impact(.light) }
        }
    }
}
