import UIKit

/// Multi-scene-safe access to the active screen's metrics, replacing the
/// deprecated `UIScreen.main`. Falls back to sensible defaults if no foreground
/// window scene is available (e.g. very early in launch).
@MainActor
enum ScreenMetrics {
    /// Scene resolution walks every connected scene, so the result is cached
    /// briefly: prefetch sizing reads `pixelSize` per image request, and the
    /// active screen can't meaningfully change within the TTL (worst case is
    /// a slightly-off thumbnail size for a moment after a scene transition).
    private static var screenCache: (screen: UIScreen?, at: Date)?
    private static let screenCacheTTL: TimeInterval = 2

    /// E5: resolve the scene from the app's key window, not "any foreground
    /// scene". `scenes.first` could pick an external-display scene (huge
    /// pixel size → oversized prefetch decodes) or the wrong scene under Split
    /// View/Stage Manager, where multiple scenes report `.foregroundActive`.
    private static var screen: UIScreen? {
        if let cache = screenCache, Date().timeIntervalSince(cache.at) < screenCacheTTL {
            return cache.screen
        }
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let keyWindowScene = scenes.first(where: { scene in
            scene.windows.contains(where: \.isKeyWindow)
        })
        let resolved = (keyWindowScene ?? scenes.first)?.screen
        screenCache = (resolved, Date())
        return resolved
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
