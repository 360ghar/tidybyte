import Foundation
import Observation

/// A navigation target reachable from outside the app's own UI — widget taps
/// (via `onOpenURL`) and App Intents (via `PendingRoute`). Both funnel through
/// `AppNavigation.handle(_:)` so there's a single routing code path.
enum DeepLink: Sendable, Equatable {
    case storage
    case activity
    case swipe
    case cleanupHome
    case cleanupTool(CleanupTool)

    /// Parses `tidybyte://<host>[/<tool>]` URLs used by the widget.
    static func from(url: URL) -> DeepLink? {
        guard url.scheme == "tidybyte" else { return nil }
        switch url.host {
        case "storage": return .storage
        case "activity": return .activity
        case "swipe": return .swipe
        case "cleanup":
            if let segment = url.pathComponents.first(where: { $0 != "/" }),
               let tool = CleanupTool(rawValue: segment) {
                return .cleanupTool(tool)
            }
            return .cleanupHome
        default:
            return nil
        }
    }
}

/// Holds a deep link set by an App Intent until `RootView` can apply it.
/// Observable so the view reacts whether the intent's `perform()` runs before
/// the view appears (drained by `.task`) or after (caught by `.onChange`) — the
/// ordering isn't guaranteed for `openAppWhenRun` intents.
@MainActor
@Observable
final class PendingRoute {
    static let shared = PendingRoute()
    private init() {}

    var link: DeepLink?

    func consume() -> DeepLink? {
        defer { link = nil }
        return link
    }
}
