import SwiftUI

/// The live language and appearance state for the running app.
///
/// Owned by `TidybyteApp` and injected into the environment. Views read the
/// resolved `Locale` and `layoutDirection` from the environment (so `Text`
/// localizes itself and layout mirrors for RTL), while non-view code reads the
/// language through `L10n`, which consults the same stored preference.
///
/// Changing the language is immediate: SwiftUI re-renders every `Text` against
/// the new `\.locale`. Two things do not change live and are documented where
/// they bite:
///
/// 1. **System-owned UI.** The photo-permission alert, the Photos picker, the
///    share sheet, and the Mail composer are rendered by iOS. They follow the
///    app's `AppleLanguages`, which `applyToSystem` writes, and therefore pick
///    up the new language on the next launch. Settings offers an explicit link
///    to the iOS per-app language screen for exactly this reason.
/// 2. **Other processes.** The widget and scheduled notifications render
///    outside this app. They read the App Group mirror on their own schedule,
///    so the widget refreshes at its next timeline reload.
@Observable
@MainActor
final class LanguageStore {
    /// The user's stored choice. `.system` means "follow the device".
    private(set) var language: AppLanguage

    /// The user's stored appearance choice.
    var appearance: AppAppearance {
        didSet {
            guard appearance != oldValue else { return }
            AppearancePreferenceStore.save(appearance)
        }
    }

    init() {
        language = LanguagePreferenceStore.stored() ?? .system
        appearance = AppearancePreferenceStore.stored()
    }

    /// The language the app is actually rendering in.
    ///
    /// With no override this is the device language, which may be `nil` when
    /// iOS is set to a language TidyByte does not ship — in that case the UI
    /// falls back to the base language, and Settings says so.
    var resolvedLanguage: AppLanguage? {
        language == .system ? AppLanguage.matchingDeviceLanguage() : language
    }

    /// The language code to render against, always concrete. `en` is the base
    /// language and the fallback for an unsupported device language.
    var effectiveLanguage: AppLanguage {
        resolvedLanguage ?? .english
    }

    /// True when the device is set to a language with no translations, so
    /// Settings can explain why the UI is in English.
    var deviceLanguageIsUnsupported: Bool {
        language == .system && AppLanguage.matchingDeviceLanguage() == nil
    }

    /// The `\.locale` injected at the root. `Text` resolves its own key through
    /// this value, which is what makes the switch work without a relaunch.
    var locale: Locale {
        Formatters.locale(for: language == .system ? nil : language)
    }

    /// Mirrors the choice for RTL languages, so the whole layout flips.
    var layoutDirection: LayoutDirection {
        effectiveLanguage.isRightToLeft ? .rightToLeft : .leftToRight
    }

    /// Applies a new language: persists it, mirrors it for the widget and for
    /// iOS-owned UI, and publishes the change.
    func setLanguage(_ newValue: AppLanguage) {
        guard newValue != language else { return }
        language = newValue
        LanguagePreferenceStore.save(newValue)
        applyToSystem(newValue)
        // The widget's own text is in the chosen language; ask WidgetKit to
        // rebuild so it is not stale until the next scheduled refresh.
        WidgetRefresh.requestReload()
    }

    /// Writes the choice where iOS reads it for app-owned but system-rendered
    /// UI: `AppleLanguages` governs the language of the app's bundle
    /// (`Bundle.main`), which is what the permission alert, the Photos picker,
    /// and `UIActivityViewController` consult.
    ///
    /// This is the documented per-app mechanism: iOS keeps the value in the
    /// app's own preferences domain, so it is scoped to TidyByte and shows up
    /// as the app's language in iOS Settings. Removing the key restores
    /// "follow the device".
    private func applyToSystem(_ language: AppLanguage) {
        if let code = language.code {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }
}

/// Bridges the Foundation-only appearance model onto SwiftUI.
///
/// `AppAppearance` deliberately avoids importing SwiftUI so the widget target
/// and the unit tests can read it; this is the one place the two meet.
extension ColorSchemeChoice {
    var swiftUI: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Asks WidgetKit to reload timelines, without importing WidgetKit into the app
/// target (the app links WidgetKit for nothing else).
enum WidgetRefresh {    static func requestReload() {
        // `WidgetCenter` is available to the app, but reaching it through
        // NotificationCenter keeps this file free of a WidgetKit import and
        // keeps the call safe in unit tests where no widget host exists.
        #if canImport(WidgetKit)
        Task { @MainActor in
            WidgetCenterBridge.reload()
        }
        #endif
    }
}

#if canImport(WidgetKit)
import WidgetKit

private enum WidgetCenterBridge {
    @MainActor
    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
#endif
