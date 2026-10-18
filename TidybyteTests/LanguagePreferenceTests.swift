import XCTest
@testable import Tidybyte

/// Pins the language-resolution rules, which decide what a fresh install shows
/// before the user touches anything.
final class AppLanguageTests: XCTestCase {

    // MARK: - Device matching

    func testExactCodeMatches() {
        XCTAssertEqual(AppLanguage.match(identifier: "hi"), .hindi)
        XCTAssertEqual(AppLanguage.match(identifier: "de"), .german)
        XCTAssertEqual(AppLanguage.match(identifier: "ja"), .japanese)
    }

    func testRegionSubtagIsIgnored() {
        // A device set to German-in-Austria must get German, not the fallback.
        XCTAssertEqual(AppLanguage.match(identifier: "de-AT"), .german)
        XCTAssertEqual(AppLanguage.match(identifier: "fr-CA"), .french)
        XCTAssertEqual(AppLanguage.match(identifier: "en-GB"), .english)
        // Underscore form is what `Locale.preferredLanguages` sometimes yields.
        XCTAssertEqual(AppLanguage.match(identifier: "en_US"), .english)
    }

    func testPortugueseVariantsAllResolveToTheShippedVariant() {
        // `pt-BR` is the only Portuguese we ship; every other variant is far
        // closer to it than to English.
        XCTAssertEqual(AppLanguage.match(identifier: "pt"), .portugueseBrazil)
        XCTAssertEqual(AppLanguage.match(identifier: "pt-PT"), .portugueseBrazil)
        XCTAssertEqual(AppLanguage.match(identifier: "pt-BR"), .portugueseBrazil)
    }

    func testChineseScriptDecidesTheVariant() {
        XCTAssertEqual(AppLanguage.match(identifier: "zh-Hans"), .chineseSimplified)
        XCTAssertEqual(AppLanguage.match(identifier: "zh-CN"), .chineseSimplified)
        XCTAssertEqual(AppLanguage.match(identifier: "zh-SG"), .chineseSimplified)
        // Traditional is deliberately unsupported: showing Simplified to a
        // Traditional reader is worse than falling back to English.
        XCTAssertNil(AppLanguage.match(identifier: "zh-Hant"))
        XCTAssertNil(AppLanguage.match(identifier: "zh-TW"))
        XCTAssertNil(AppLanguage.match(identifier: "zh-HK"))
    }

    func testUnshippedLanguageDoesNotMatch() {
        XCTAssertNil(AppLanguage.match(identifier: "th"))
        XCTAssertNil(AppLanguage.match(identifier: "vi"))
        XCTAssertNil(AppLanguage.match(identifier: ""))
    }

    func testDeviceLanguageWalksThePreferenceList() {
        // The first entry is unsupported, so the second must win — otherwise a
        // device set to ["pt-PT", "en-GB"] would fall back to English by
        // accident rather than by decision.
        XCTAssertEqual(
            AppLanguage.matchingDeviceLanguage(preferred: ["pt-PT", "en-GB"]),
            .portugueseBrazil
        )
        XCTAssertEqual(
            AppLanguage.matchingDeviceLanguage(preferred: ["th", "fr"]),
            .french
        )
        XCTAssertNil(AppLanguage.matchingDeviceLanguage(preferred: ["th", "vi"]))
    }

    // MARK: - Shape

    func testEveryLanguageExceptSystemHasTranslations() {
        // `system` is a mode, not a language, so it must not appear in the
        // picker or in the translation coverage checks.
        XCTAssertFalse(AppLanguage.concreteLanguages.contains(.system))
        XCTAssertEqual(AppLanguage.concreteLanguages.count, AppLanguage.allCases.count - 1)
    }

    func testRightToLeftLanguagesAreMarked() {
        XCTAssertTrue(AppLanguage.arabic.isRightToLeft)
        XCTAssertTrue(AppLanguage.hebrew.isRightToLeft)
        // Persian and Urdu are RTL too but are not shipped; the shipped
        // left-to-right set must not be mislabelled.
        for language in AppLanguage.concreteLanguages where language != .arabic && language != .hebrew {
            XCTAssertFalse(language.isRightToLeft, "\(language.rawValue) must not be right-to-left")
        }
    }

    func testEndonymsAreNotTranslated() {
        // The picker must be usable by someone who cannot read the current UI
        // language, so each endonym has to stay in its own script regardless of
        // the active language.
        XCTAssertEqual(AppLanguage.japanese.endonym, "日本語")
        XCTAssertEqual(AppLanguage.arabic.endonym, "العربية")
        XCTAssertEqual(AppLanguage.hindi.endonym, "हिन्दी")
        XCTAssertEqual(AppLanguage.english.endonym, "English")
    }

    func testCodeIsNilOnlyForSystem() {
        XCTAssertNil(AppLanguage.system.code)
        for language in AppLanguage.concreteLanguages {
            XCTAssertEqual(language.code, language.rawValue)
        }
    }
}

/// The stored preference: absent means "follow the device", and a value we no
/// longer recognize must not brick the UI.
final class LanguagePreferenceStoreTests: XCTestCase {
    private var suite: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "LanguagePreferenceStoreTests.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testAbsentMeansNoOverride() {
        XCTAssertNil(LanguagePreferenceStore.stored(in: suite))
    }

    func testSavedLanguageRoundTrips() {
        LanguagePreferenceStore.save(.german, to: suite)
        XCTAssertEqual(LanguagePreferenceStore.stored(in: suite), .german)
    }

    func testSavingSystemClearsTheOverride() {
        LanguagePreferenceStore.save(.german, to: suite)
        LanguagePreferenceStore.save(.system, to: suite)
        // "Automatic" and a fresh install must behave identically, so the key
        // is removed rather than stored as "system".
        XCTAssertNil(suite.string(forKey: LanguagePreferenceStore.key))
        XCTAssertNil(LanguagePreferenceStore.stored(in: suite))
    }

    func testUnrecognizedStoredValueFallsBackToNoOverride() {
        // A language removed in a later version, or a hand-edited preference.
        suite.set("kl-GL", forKey: LanguagePreferenceStore.key)
        XCTAssertNil(LanguagePreferenceStore.stored(in: suite))
    }

    func testStoredSystemStringIsTreatedAsNoOverride() {
        suite.set(AppLanguage.system.rawValue, forKey: LanguagePreferenceStore.key)
        XCTAssertNil(LanguagePreferenceStore.stored(in: suite))
    }
}

/// The appearance picker, whose default must remain "follow the device".
final class AppearancePreferenceTests: XCTestCase {
    private var suite: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AppearancePreferenceTests.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultFollowsTheDevice() {
        XCTAssertEqual(AppearancePreferenceStore.stored(in: suite), .system)
        XCTAssertNil(AppAppearance.system.colorScheme, "system must leave the scheme unset so iOS stays in charge")
    }

    func testOverrideRoundTrips() {
        AppearancePreferenceStore.save(.dark, to: suite)
        XCTAssertEqual(AppearancePreferenceStore.stored(in: suite), .dark)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }

    func testSavingSystemClearsTheOverride() {
        AppearancePreferenceStore.save(.dark, to: suite)
        AppearancePreferenceStore.save(.system, to: suite)
        XCTAssertNil(suite.string(forKey: AppearancePreferenceStore.key))
    }

    func testUnrecognizedValueFallsBackToSystem() {
        suite.set("sepia", forKey: AppearancePreferenceStore.key)
        XCTAssertEqual(AppearancePreferenceStore.stored(in: suite), .system)
    }
}

/// Haptics default to on, because that is what every build before the setting
/// did. An absent key must not read as "off".
final class HapticsPreferenceTests: XCTestCase {
    private var suite: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "HapticsPreferenceTests.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testAbsentKeyMeansEnabled() {
        XCTAssertTrue(AppPreferences.hapticsEnabled(in: suite))
    }

    func testExplicitFalseIsHonored() {
        // `bool(forKey:)` cannot tell absent from an explicit false, which is
        // why the implementation reads `object(forKey:)`.
        AppPreferences.saveHapticsEnabled(false, in: suite)
        XCTAssertFalse(AppPreferences.hapticsEnabled(in: suite))
    }

    func testExplicitTrueIsHonored() {
        AppPreferences.saveHapticsEnabled(true, in: suite)
        XCTAssertTrue(AppPreferences.hapticsEnabled(in: suite))
    }
}
