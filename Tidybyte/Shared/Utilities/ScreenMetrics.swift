import UIKit

/// Multi-scene-safe access to the active screen's metrics, replacing the
/// deprecated `UIScreen.main`. Falls back to sensible defaults if no foreground
/// window scene is available (e.g. very early in launch).
@MainActor
enum ScreenMetrics {
    private static var screen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })?.screen
            ?? scenes.first?.screen
    }

    /// Point size of the active screen.
    static var size: CGSize {
        screen?.bounds.size ?? CGSize(width: 390, height: 844)
    }

    /// Native scale factor of the active screen.
    static var scale: CGFloat {
        screen?.scale ?? 3
    }

    /// Pixel size of the active screen (points × scale) — the right target size
    /// for full-screen image requests.
    static var pixelSize: CGSize {
        let points = size
        let scaleFactor = scale
        return CGSize(width: points.width * scaleFactor, height: points.height * scaleFactor)
    }
}
