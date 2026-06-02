import Foundation

/// Shared App Group storage for the cross-target `WidgetSnapshot`. The main app
/// writes; the widget reads. Dependency-free (Foundation only) so it stays light
/// enough to compile into the widget extension. Compiled into BOTH targets.
enum AppGroupStore {
    static let suiteName = "group.com.sakshammittal.tidybyte.shared"
    static let snapshotKey = "widget.snapshot.v1"

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
}
