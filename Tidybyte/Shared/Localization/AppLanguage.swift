import Foundation

/// Every language TidyByte ships UI for, plus `.system`.
///
/// `.system` is the default and means "follow the device": the app renders in
/// whatever language iOS resolves for it, which is the device language unless
/// the user picked a per-app language in iOS Settings. Every other case is an
/// explicit override chosen in TidyByte's own Settings screen.
///
/// The raw values are BCP-47 language identifiers and must match the
/// localization identifiers declared in `Localizable.xcstrings` (`hi`,
/// `pt-BR`, `zh-Hans`, …). `LanguageCoverageTests` fails when a case has no
/// translations, so adding a language here without translating it is a build
/// error rather than a silent English fallback.
///
/// This type is Foundation-only and compiled into the widget extension as well
/// as the app, so both processes resolve the same language from the same
/// stored preference.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case hindi = "hi"
    case bengali = "bn"
    case tamil = "ta"
    case telugu = "te"
    case marathi = "mr"
    case gujarati = "gu"
    case kannada = "kn"
    case malayalam = "ml"
    case punjabi = "pa"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case portugueseBrazil = "pt-BR"
    case italian = "it"
    case japanese = "ja"
    case korean = "ko"
    case chineseSimplified = "zh-Hans"
    case russian = "ru"
    case arabic = "ar"
    case hebrew = "he"

    var id: String { rawValue }

    /// The concrete language code, or `nil` for `.system`.
    var code: String? { self == .system ? nil : rawValue }

    /// The languages that actually have translations. `.system` is excluded
    /// because it is a mode, not a language.
    static var concreteLanguages: [AppLanguage] {
        allCases.filter { $0 != .system }
    }

    /// The language's name in its own script.
    ///
    /// Deliberately never translated. A user hunting for their language scans
    /// for the endonym; rendering "Japanese" in Japanese-for-someone-who-reads-
    /// English helps nobody, and rendering it in the *current* UI language
    /// means a user stuck in a language they cannot read cannot find their way
    /// out. Endonyms are the one string in the app that must stay constant.
    var endonym: String {
        switch self {
        case .system: "Automatic"
        case .english: "English"
        case .hindi: "हिन्दी"
        case .bengali: "বাংলা"
        case .tamil: "தமிழ்"
        case .telugu: "తెలుగు"
        case .marathi: "मराठी"
        case .gujarati: "ગુજરાતી"
        case .kannada: "ಕನ್ನಡ"
        case .malayalam: "മലയാളം"
        case .punjabi: "ਪੰਜਾਬੀ"
        case .spanish: "Español"
        case .french: "Français"
        case .german: "Deutsch"
        case .portugueseBrazil: "Português (Brasil)"
        case .italian: "Italiano"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .chineseSimplified: "简体中文"
        case .russian: "Русский"
        case .arabic: "العربية"
        case .hebrew: "עברית"
        }
    }

    /// Languages written right to left. Drives the layout direction the app
    /// injects at the root; see `LanguageStore.layoutDirection`.
    var isRightToLeft: Bool {
        switch self {
        case .arabic, .hebrew: true
        default: false
        }
    }

    /// The device's language as one of ours, or `nil` when iOS is set to a
    /// language TidyByte does not ship.
    ///
    /// Matching walks the device's full preference list, so a device set to
    /// `["pt-PT", "en-GB"]` lands on English rather than falling back to
    /// English by accident — and a device set to `["pt-PT"]` alone correctly
    /// reports "not supported" so Settings can say so.
    static func matchingDeviceLanguage(preferred: [String] = Locale.preferredLanguages) -> AppLanguage? {
        for identifier in preferred {
            if let match = match(identifier: identifier) { return match }
        }
        return nil
    }

    /// Maps a single BCP-47 identifier onto a shipped language, ignoring region
    /// and script subtags that we do not differentiate on.
    ///
    /// Two cases get special handling:
    ///
    /// - `pt-BR` is the only Portuguese we ship, so every Portuguese variant
    ///   resolves to it.
    /// - Chinese resolves by script *and* by region. `zh-Hant`, `zh-TW`,
    ///   `zh-HK` and `zh-MO` are Traditional and deliberately do not match:
    ///   showing Simplified to a Traditional reader is worse than falling back
    ///   to English, which at least is a language they may read. An explicit
    ///   `Hans` script outranks the region, so `zh-Hans-HK` and `zh-Hans-TW`
    ///   resolve to Simplified rather than falling back.
    static func match(identifier: String) -> AppLanguage? {
        let tag = identifier.replacingOccurrences(of: "_", with: "-")
        let parts = tag.split(separator: "-").map(String.init)
        guard let base = parts.first?.lowercased() else { return nil }

        if base == "zh" {
            let subtags = parts.dropFirst().map { $0.lowercased() }
            if subtags.contains("hant") { return nil }
            // An explicit script wins over the region. `zh-Hans-HK`,
            // `zh-Hans-MO` and `zh-Hans-TW` name Simplified directly, so the
            // Traditional-region rule below must not override them into the
            // English fallback.
            if subtags.contains("hans") { return .chineseSimplified }
            // Regions that imply Traditional even without a script subtag.
            let traditionalRegions: Set<String> = ["tw", "hk", "mo"]
            if subtags.contains(where: { traditionalRegions.contains($0) }) { return nil }
            return .chineseSimplified
        }

        switch base {
        case "en": return .english
        case "hi": return .hindi
        case "bn": return .bengali
        case "ta": return .tamil
        case "te": return .telugu
        case "mr": return .marathi
        case "gu": return .gujarati
        case "kn": return .kannada
        case "ml": return .malayalam
        case "pa": return .punjabi
        case "es": return .spanish
        case "fr": return .french
        case "de": return .german
        case "pt": return .portugueseBrazil
        case "it": return .italian
        case "ja": return .japanese
        case "ko": return .korean
        case "ru": return .russian
        case "ar": return .arabic
        case "he": return .hebrew
        default: return nil
        }
    }
}
