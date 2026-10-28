import Foundation

/// The stored language choice, shared between the app and the widget.
///
/// Two processes need this value: the app renders the UI, and the widget
/// extension renders its own views in a separate process with its own
/// `UserDefaults`. The App Group suite is the shared channel; `.standard` is
/// also written so unit tests can inject a scratch suite and so the app still
/// works if the App Group entitlement is missing (same defensive posture as
/// `AppGroupStore.defaults`).
///
/// Foundation-only on purpose: this file compiles into the widget target too.
enum LanguagePreferenceStore {
    /// Defined here rather than in `AppPreferences`: that enum lives in the app
    /// target only, and the widget needs to read the same key.
    static let key = "appLanguagePreference"

    /// Writes the choice to both stores. `nil` means "follow the device", which
    /// is stored as an absent key so a fresh install and an explicit "Automatic"
    /// pick are indistinguishable — they should behave identically.
    static func save(_ language: AppLanguage?, to defaults: UserDefaults = AppGroupStore.defaults) {
        let code = language?.code
        write(code, to: defaults)
        // Mirror to the app-local store as well; see the type comment.
        if defaults !== UserDefaults.standard {
            write(code, to: .standard)
        }
    }

    private static func write(_ code: String?, to defaults: UserDefaults) {
        if let code {
            defaults.set(code, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// The stored override, or `nil` when the app should follow the device.
    ///
    /// An unrecognized stored string (a language we removed, or a hand-edited
    /// preference) resolves to `nil` rather than trapping, so a downgrade
    /// cannot brick the UI into a missing-localization state.
    static func stored(in defaults: UserDefaults? = nil) -> AppLanguage? {
        if let defaults {
            return decode(defaults.string(forKey: key))
        }
        return decode(AppGroupStore.defaults.string(forKey: key))
            ?? decode(UserDefaults.standard.string(forKey: key))
    }

    private static func decode(_ raw: String?) -> AppLanguage? {
        guard let raw, let language = AppLanguage(rawValue: raw), language != .system else { return nil }
        return language
    }
}
