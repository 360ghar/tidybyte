import Foundation

/// The app's appearance choice.
///
/// `.system` is the default, which is the existing behavior: the app already
/// follows the device because nothing sets `preferredColorScheme` globally.
/// This type adds the ability to override it, and nothing else changes.
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// The picker row's text.
    ///
    /// `L10n.string` with the English text as the key, which is the project's
    /// convention (see `BlurSensitivity.displayName`). English-as-key rather
    /// than a symbolic key like `"appearance.light"`: a symbolic key has to be
    /// added to the catalog by hand, and until it is, SwiftUI renders the raw
    /// key on screen — the picker showed `appearance.light` instead of "Light".
    ///
    /// Resolved through `L10n` rather than `Text` because this is a `String`
    /// computed property read by a picker, not a literal in a `Text` call, so
    /// there is no `\.locale` environment to resolve against. `L10n` reads the
    /// stored language instead, which the live switch updates before the view
    /// tree rebuilds.
    ///
    /// "Automatic" reuses the existing catalog entry, and matches the wording
    /// of iOS's own Appearance picker.
    var displayName: String {
        switch self {
        case .system: L10n.string("Automatic")
        case .light: L10n.string("Light")
        case .dark: L10n.string("Dark")
        }
    }

    /// The value `preferredColorScheme` wants: `nil` follows the device.
    ///
    /// Returning `nil` rather than a resolved scheme is the point — it keeps
    /// iOS in charge, so the app keeps following the device's light/dark switch
    /// and any automatic schedule (sunset to sunrise) instead of freezing at
    /// whatever the device was doing when the app launched.
    var colorScheme: ColorSchemeChoice? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// `ColorScheme` without importing SwiftUI, so this file stays Foundation-only
/// and can be unit-tested and read from the widget target.
enum ColorSchemeChoice: String, Sendable {
    case light
    case dark
}

/// The stored appearance choice.
///
/// Unlike the language, this does not need an App Group mirror: the widget
/// renders in the system's appearance by design (a widget that ignores the
/// device's dark mode looks broken on the Home Screen), and it never reads this
/// value.
enum AppearancePreferenceStore {
    /// Shared with `AppPreferences.Key`, but declared here so the widget-safe
    /// part of the module does not depend on the app-only enum.
    static let key = "appAppearancePreference"

    static func save(_ appearance: AppAppearance, to defaults: UserDefaults = .standard) {
        if appearance == .system {
            // Absent means "follow the device", so an explicit "System" pick and
            // a fresh install behave identically.
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(appearance.rawValue, forKey: key)
        }
    }

    /// Unrecognized values resolve to `.system` rather than trapping.
    static func stored(in defaults: UserDefaults = .standard) -> AppAppearance {
        guard let raw = defaults.string(forKey: key),
              let appearance = AppAppearance(rawValue: raw) else { return .system }
        return appearance
    }
}
