import Foundation

/// A route the widget asks the app to open. The widget extension performs its
/// `AppIntent` in the app's process (`openAppWhenRun = true`), but the intent is
/// compiled into the widget target and therefore can't reference the app's
/// `DeepLink` / `PendingRoute` types — so it writes one of these to the App
/// Group and the app drains it on activation. Works whether the launch is cold
/// or warm.
enum WidgetRoute: String {
    case swipe
    case screenshots
    case activity
}

/// Shared App Group storage for the cross-target `WidgetSnapshot`. The main app
/// writes; the widget reads. Dependency-free (Foundation only) so it stays light
/// enough to compile into the widget extension. Compiled into BOTH targets.
enum AppGroupStore {
    static let suiteName = "group.com.sakshammittal.tidybyte.shared"
    static let snapshotKey = "widget.snapshot.v1"
    static let pendingRouteKey = "widget.pendingRoute.v1"

    static var defaults: UserDefaults {
        // Falls back to .standard if the App Group entitlement is missing (e.g.
        // a build without the capability) so calls stay safe no-ops rather than
        // crashing.
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func loadSnapshot() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    // MARK: - Widget → App Route Handoff

    static func savePendingRoute(_ route: WidgetRoute) {
        defaults.set(route.rawValue, forKey: pendingRouteKey)
    }

    /// Returns the queued route and clears it, so a single widget tap can't
    /// re-open the same destination on every subsequent activation.
    static func consumePendingRoute() -> WidgetRoute? {
        defer { defaults.removeObject(forKey: pendingRouteKey) }
        guard let raw = defaults.string(forKey: pendingRouteKey) else { return nil }
        return WidgetRoute(rawValue: raw)
    }
}
