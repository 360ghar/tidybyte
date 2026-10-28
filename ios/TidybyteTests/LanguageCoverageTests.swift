import XCTest
@testable import Tidybyte

/// The guard `AppLanguage` and `L10n` name in their doc comments.
///
/// Both types promise that a case added without translations is a build error
/// rather than a silent English fallback. Nothing checked that: a missing
/// `.lproj` makes `L10n.bundle(for:)` degrade to `Bundle.main`, which renders
/// English and looks fine in a simulator set to English. This asserts the two
/// halves of the promise directly, per language:
///
/// 1. the language ships a `.lproj` in the app bundle, and
/// 2. a key that every screen relies on resolves to something other than the
///    English source, so an empty or half-filled `.lproj` cannot pass either.
final class LanguageCoverageTests: XCTestCase {

    /// Chosen because it is on the first screen a user sees and is translated in
    /// every shipped language; a key nothing looks up would pass this test while
    /// the UI stayed English.
    private let sentinel = "Continue"

    /// The bundle carrying the shipped `.lproj` directories.
    ///
    /// The unit-test bundle is hosted by the app, so `Bundle.main` is the app.
    /// The scan keeps the test honest if that ever changes, rather than letting
    /// it pass by resolving the sentinel out of the wrong bundle.
    private static let appBundle: Bundle = {
        for candidate in [Bundle.main, Bundle(for: LanguageCoverageTests.self)] {
            if candidate.path(forResource: "de", ofType: "lproj") != nil { return candidate }
        }
        return .main
    }()

    func testEveryShippedLanguageHasAnLPROJInTheAppBundle() {
        for language in AppLanguage.concreteLanguages {
            XCTAssertNotNil(
                Self.appBundle.path(forResource: language.rawValue, ofType: "lproj"),
                "\(language.rawValue) is in AppLanguage.concreteLanguages but the app bundle has no \(language.rawValue).lproj, so it renders English"
            )
        }
    }

    func testTheSentinelIsItsOwnEnglishSourceString() {
        XCTAssertEqual(
            L10n.string(sentinel, language: .english),
            sentinel,
            "the sentinel must be keyed on its English text, or the comparison below proves nothing"
        )
    }

    func testEveryShippedLanguageTranslatesTheSentinel() {
        for language in AppLanguage.concreteLanguages where language != .english {
            let translated = L10n.string(sentinel, language: language)
            XCTAssertNotEqual(
                translated,
                sentinel,
                "\(language.rawValue) does not translate \"\(sentinel)\", so the app falls back to English there"
            )
            XCTAssertFalse(
                translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(language.rawValue) has an empty translation for \"\(sentinel)\""
            )
        }
    }
}
