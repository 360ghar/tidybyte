import Foundation

/// String lookup for code that runs outside a SwiftUI view.
///
/// Inside a view, `Text("key")` is the right call: SwiftUI resolves it against
/// the `\.locale` environment value, so the language can change while the app
/// is running (verified in the simulator — an injected `de` locale renders the
/// German string immediately, no relaunch). Services, notification bodies,
/// widget copy, and App Intents have no such environment, so they come here.
///
/// **Navigation titles are the exception, and they come here too.** A
/// `.navigationTitle("key")` takes the same `LocalizedStringKey`, but the bar is
/// UIKit-backed and only re-applies a title whose *value* changed. That key is
/// identical in every language, so a screen that was hidden while the language
/// changed keeps the old title when the user comes back to it: the body
/// re-renders in the new language while the bar still reads the old one. Passing
/// `string(_:)` instead makes the value differ per language, so the title is
/// re-applied. Every `.navigationTitle` in the app does this — keep it that way,
/// and prefer `CleanupTool.name`-style computed properties over literals.
///
/// This type resolves against the *specific language's* bundle rather than
/// `Bundle.main`. That matters for the same reason: `Bundle.main` resolves once
/// per process launch, so it keeps serving the launch-time language after the
/// user switches. Building a `Bundle` from the chosen `.lproj` directory is the
/// only way to get the new language without a relaunch.
enum L10n {
    /// The language to resolve against: the user's override if they set one,
    /// otherwise `nil` meaning "whatever iOS already resolved for this
    /// process" (`Bundle.main` is correct in that case, including per-app
    /// language set in iOS Settings).
    static var currentOverride: AppLanguage? { LanguagePreferenceStore.stored() }

    /// The bundle for a language, or `Bundle.main` when there is no override.
    ///
    /// Caches per language because this is called on hot paths (every size
    /// string in a list of thousands of assets). `Bundle(path:)` is not free
    /// and the answer never changes within a process for a given language.
    private static let cache = BundleCache()

    static func bundle(for language: AppLanguage?) -> Bundle {
        guard let language, language != .system else { return .main }
        return cache.bundle(for: language)
    }

    /// Looks up `key` in the language's bundle.
    ///
    /// `value` is the English fallback. Passing the English text here (rather
    /// than an empty string) is deliberate: it keeps a missing translation
    /// readable instead of showing a raw key to the user, and it matches what
    /// the String Catalog would have produced anyway.
    static func string(_ key: String, language: AppLanguage? = nil, fallback: String? = nil) -> String {
        let bundle = bundle(for: language ?? currentOverride)
        let resolved = bundle.localizedString(forKey: key, value: fallback ?? key, table: nil)
        // `localizedString` returns the key itself when the table has no entry.
        // Falling back to the key is fine for the base language (where the key
        // IS the English text) but useless for anything else, so let the caller
        // supply the English text when the key is not itself English.
        return resolved
    }

    /// A localized template with `%` arguments applied, for counted strings.
    ///
    /// Goes through `String.localizedStringWithFormat` rather than
    /// `String(format:)` so plural rules from the String Catalog are applied:
    /// the catalog compiles plural variations into a `.stringsdict`, and only
    /// `localizedStringWithFormat` consults it.
    ///
    /// - Important: **Known limitation.** The plural *variants* come from the
    ///   right language's `.stringsdict`, but the *category selection* uses
    ///   `Locale.current`, and no Foundation API takes a locale for that. So a
    ///   user who picks a language in Settings that differs from their device
    ///   language gets the device language's plural rules applied to the chosen
    ///   language's forms.
    ///
    ///   Verified on macOS/iOS 27 with a hand-built `.stringsdict`: with an
    ///   English device locale and a Russian app language, `5` renders
    ///   `5 элемента` (the `few` form) instead of `5 элементов` (the `many`
    ///   form English rules never select). Arabic and Hebrew are affected the
    ///   same way. Japanese, Korean, and Simplified Chinese are **not**: their
    ///   `.stringsdict` carries only `other`, so a rule that selects `one`
    ///   falls back to `other` and the output is correct.
    ///
    ///   Fixing this needs CLDR category selection in Swift plus reading the
    ///   variant out of the shipped `.stringsdict` (which is a plain plist in
    ///   the bundle). That is a real subsystem, and a hand-rolled plural engine
    ///   that is wrong for some count is worse than this limitation, so it is
    ///   documented rather than half-implemented.
    static func format(_ key: String, language: AppLanguage? = nil, fallback: String? = nil, _ arguments: CVarArg...) -> String {
        let template = string(key, language: language, fallback: fallback)
        return String.localizedStringWithFormat(template, arguments)
    }

    /// The same, with the arguments already collected — for callers that build
    /// an argument list dynamically.
    static func format(_ key: String, language: AppLanguage? = nil, fallback: String? = nil, arguments: [CVarArg]) -> String {
        let template = string(key, language: language, fallback: fallback)
        return String.localizedStringWithFormat(template, arguments)
    }

    /// A bundle for the language iOS would pick with no override at all, which
    /// is what a fresh install shows. Used by tests to assert the base
    /// language, and by Settings to name the language the device is on.
    static var deviceLanguage: AppLanguage? {
        AppLanguage.matchingDeviceLanguage()
    }
}

/// Thread-safe bundle cache. `Bundle` is immutable once created, so the only
/// shared state is the dictionary itself; a lock keeps it correct without
/// pulling the whole type onto an actor (it is read from services on background
/// executors and from `@MainActor` views alike).
private final class BundleCache: @unchecked Sendable {
    private let lock = NSLock()
    private var bundles: [String: Bundle] = [:]

    func bundle(for language: AppLanguage) -> Bundle {
        lock.lock()
        defer { lock.unlock() }
        if let cached = bundles[language.rawValue] { return cached }
        // `Bundle(path:)` fails only if the .lproj directory is missing, which
        // means the catalog has no translations for this language — a build
        // misconfiguration that `LanguageCoverageTests` catches. Degrading to
        // the main bundle keeps the app usable rather than crashing.
        let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj")
        let bundle = path.flatMap(Bundle.init(path:)) ?? .main
        bundles[language.rawValue] = bundle
        return bundle
    }
}
