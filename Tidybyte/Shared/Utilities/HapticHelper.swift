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

    // All callers are already on the main actor (views and @MainActor view
    // models), so make that explicit.
    @MainActor
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
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
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @MainActor
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
