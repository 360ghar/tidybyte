import UIKit

enum HapticHelper {
    /// One generator per style, reused and kept prepared.
    ///
    /// Building a fresh generator per call means the Taptic Engine has not spun
    /// up yet, so the impact lands late. That latency is most noticeable on the
    /// drag-start feedback, whose whole job is to confirm the gesture began.
    /// UIFeedbackGenerator is main-actor-isolated, so the cache is too.
    @MainActor
    private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    /// The user's haptics preference, cached so the hot path does not read
    /// `UserDefaults` on every swipe.
    ///
    /// Refreshed by `SettingsView` when the toggle flips, and read once lazily
    /// on first use so a launch with haptics off never fires one before the
    /// cache is warm. `@MainActor` because every caller already is.
    @MainActor
    private static var isEnabledCache: Bool?

    @MainActor
    static var isEnabled: Bool {
        if let isEnabledCache { return isEnabledCache }
        let enabled = AppPreferences.hapticsEnabled()
        isEnabledCache = enabled
        return enabled
    }

    /// Called by Settings when the toggle changes, so the change takes effect
    /// immediately without the next launch.
    @MainActor
    static func refreshEnabledState() {
        isEnabledCache = AppPreferences.hapticsEnabled()
    }

    // All callers are already on the main actor (views and @MainActor view
    // models), so make that explicit.
    @MainActor
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard isEnabled else { return }
        let generator: UIImpactFeedbackGenerator
        if let existing = impactGenerators[style] {
            generator = existing
        } else {
            generator = UIImpactFeedbackGenerator(style: style)
            impactGenerators[style] = generator
        }
        generator.impactOccurred()
        // Re-arm while the engine is still warm, so the next gesture does not
        // pay the spin-up cost.
        generator.prepare()
    }

    /// Warms the engine without firing, so the first gesture's feedback is not
    /// the one that pays for starting the Taptic Engine.
    @MainActor
    static func prepare(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard isEnabled else { return }
        if let existing = impactGenerators[style] {
            existing.prepare()
        } else {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            impactGenerators[style] = generator
        }
    }

    @MainActor
    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @MainActor
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
