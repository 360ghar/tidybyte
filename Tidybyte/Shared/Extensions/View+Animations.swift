import SwiftUI

// MARK: - Fade Slide In

struct FadeSlideInModifier: ViewModifier {
    let delay: Double
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
            .onAppear {
                if reduceMotion {
                    isVisible = true
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay)) {
                        isVisible = true
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
