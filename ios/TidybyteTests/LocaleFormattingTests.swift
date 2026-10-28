import XCTest
@testable import Tidybyte

/// Pins the locale-aware formatting that replaced locale-blind formatters.
///
/// These assert against explicit locales rather than the device's, because the
/// whole point is that the output changes with the locale — a test that read
/// the device locale would pass on the developer's machine and prove nothing.
///
/// The region is passed explicitly for a second reason: `Formatters` takes the
/// language from the user's choice and the region from the device, so on a
/// US-configured simulator "German" means `de_US` — German words with US date
/// and number conventions. Asserting German *conventions* therefore requires
/// asking for a German region.
final class LocaleFormattingTests: XCTestCase {

    private let us = Locale.Region("US")
    private let de = Locale.Region("DE")
    private let fr = Locale.Region("FR")
    private let ru = Locale.Region("RU")
    private let jp = Locale.Region("JP")
    private let eg = Locale.Region("EG")

    // MARK: - File sizes

    func testSizeUsesLocaleDecimalSeparator() {
        // 1.5 MB: the separator is the visible difference between locales.
        let german = Formatters.fileSize(1_500_000, language: .german, region: de)
        let english = Formatters.fileSize(1_500_000, language: .english, region: us)
        XCTAssertTrue(german.contains("1,5"), "German uses a comma: \(german)")
        XCTAssertTrue(english.contains("1.5"), "English uses a period: \(english)")
    }

    func testSizeUsesLocaleUnitSymbol() {
        // Not a translation of the word "megabyte" — the unit symbol, which is
        // what iOS shows and what fits in a dense list row.
        XCTAssertTrue(Formatters.fileSize(1_500_000, language: .french, region: fr).contains("Mo"))
        XCTAssertTrue(Formatters.fileSize(1_500_000, language: .russian, region: ru).contains("МБ"))
        XCTAssertTrue(Formatters.fileSize(1_500_000, language: .english, region: us).contains("MB"))
    }

    func testSizeScalesUnitsByMagnitude() {
        XCTAssertTrue(Formatters.fileSize(2_500_000_000, language: .english, region: us).contains("GB"))
        XCTAssertTrue(Formatters.fileSize(1_500_000, language: .english, region: us).contains("MB"))
        XCTAssertTrue(Formatters.fileSize(20_000, language: .english, region: us).contains("kB"))
    }

    func testSizeHasNoGroupingSeparator() {
        // A size is a single measurement; "1,000 MB" reads as two numbers.
        let formatted = Formatters.fileSize(999_000_000, language: .english, region: us)
        XCTAssertFalse(formatted.contains(","), "got \(formatted)")
    }

    func testSizeNeverProducesASpelledOutUnpluralizedUnit() {
        // The regression this replaced: ByteCountFormatter has no locale, and
        // Foundation's unit formatter renders "512 byte" for English.
        for value: Int64 in [0, 1, 512, 999, 1_000] {
            let formatted = Formatters.fileSize(value, language: .english, region: us)
            XCTAssertFalse(
                formatted.lowercased().contains("byte"),
                "\(value) rendered as \(formatted); unit words cannot be pluralized reliably"
            )
        }
    }

    // MARK: - Calendar

    func testFirstWeekdayComesFromTheLocale() {
        // The bug this fixes: the reminder picker hardcoded Sunday.
        XCTAssertEqual(Formatters.firstWeekday(language: .english, region: us), 1, "US week starts Sunday")
        XCTAssertEqual(Formatters.firstWeekday(language: .german, region: de), 2, "German week starts Monday")
        XCTAssertEqual(Formatters.firstWeekday(language: .french, region: fr), 2, "French week starts Monday")
        XCTAssertEqual(Formatters.firstWeekday(language: .arabic, region: eg), 7, "Arabic week starts Saturday")
    }

    func testOrderedWeekdaysStartAtTheLocaleFirstDay() {
        let weekdaysUS = Formatters.orderedWeekdays(language: .english, region: us)
        XCTAssertEqual(weekdaysUS.count, 7)
        XCTAssertEqual(weekdaysUS.first?.weekday, 1)
        XCTAssertEqual(weekdaysUS.first?.name, "Sunday")

        let weekdaysDE = Formatters.orderedWeekdays(language: .german, region: de)
        XCTAssertEqual(weekdaysDE.first?.weekday, 2)
        XCTAssertEqual(weekdaysDE.first?.name, "Montag")

        // Every weekday number must appear exactly once, in every locale.
        for language in AppLanguage.concreteLanguages {
            let days = Formatters.orderedWeekdays(language: language)
            XCTAssertEqual(days.count, 7, "\(language.rawValue) produced \(days.count) weekdays")
            XCTAssertEqual(
                Set(days.map(\.weekday)).count, 7,
                "\(language.rawValue) has duplicate weekday numbers"
            )
        }
    }

    func testWeekdayNameResolvesAStoredPreference() {
        // The picker stores the stable weekday number and displays this.
        XCTAssertEqual(Formatters.weekdayName(2, language: .english, region: us), "Monday")
        XCTAssertEqual(Formatters.weekdayName(2, language: .german, region: de), "Montag")
        XCTAssertEqual(Formatters.weekdayName(99, language: .english), "", "out of range must not trap")
    }

    // MARK: - Time

    func testShortTimeFollowsTheLocalesClock() {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 15
        components.hour = 15
        components.minute = 0
        let date = Calendar(identifier: .gregorian).date(from: components)!

        let usTime = Formatters.shortTime(date, language: .english, region: us)
        let deTime = Formatters.shortTime(date, language: .german, region: de)
        // The reminder footer used to hardcode "10 AM", which is wrong
        // everywhere that reads a 24-hour clock.
        XCTAssertNotEqual(usTime, deTime, "12-hour and 24-hour locales must differ")
        XCTAssertTrue(usTime.contains("PM") || usTime.contains("pm"), "got \(usTime)")
        XCTAssertFalse(deTime.contains("PM") || deTime.contains("pm"), "German has no AM/PM: \(deTime)")
    }

    /// `Date.formatted(date:time:)` resolves against `Locale.current` and
    /// ignores the SwiftUI `\.locale` the app injects at the root, so six
    /// screens drew a date in the DEVICE's language under a label translated
    /// into the chosen one — "Datum" above "Oct 3, 2025".
    ///
    /// The fix only ever claims what `Formatters.locale(for:)` documents: the
    /// language comes from the in-app override, the region stays the device's.
    /// So it is language that changes the *words*, and region that changes the
    /// *pattern and clock* — asserting those separately is the difference
    /// between testing the rule and testing that two locales merely differ.
    func testDateTimeTakesWordsFromTheLanguageAndPatternFromTheRegion() {
        var components = DateComponents()
        components.year = 2025
        components.month = 10
        components.day = 3
        components.hour = 15
        components.minute = 32
        let date = Calendar(identifier: .gregorian).date(from: components)!

        // Same region (Germany), different language → different WORDS. `en_DE`
        // spells the month out, `de_DE` uses the numeric German date; that
        // difference is the bug this replaced, where a per-app language never
        // reached the formatter at all.
        let englishInGermany = Formatters.dateTime(date, language: .english, region: de)
        let germanInGermany = Formatters.dateTime(date, language: .german, region: de)
        XCTAssertTrue(englishInGermany.contains("Oct"), "got \(englishInGermany)")
        XCTAssertFalse(germanInGermany.contains("Oct"), "the German date is numeric: \(germanInGermany)")
        XCTAssertEqual(germanInGermany, "03.10.2025, 15:32", "German day-first order, 24-hour clock")

        // Same language (English), different region → different PATTERN and
        // CLOCK, even though both are English. This half is why the type does
        // not simply adopt the override's region.
        let englishInUS = Formatters.dateTime(date, language: .english, region: us)
        XCTAssertTrue(englishInUS.contains("PM") || englishInUS.contains("pm"), "US 12-hour: \(englishInUS)")
        XCTAssertFalse(
            englishInGermany.contains("PM") || englishInGermany.contains("pm"),
            "Germany keeps its 24-hour clock: \(englishInGermany)"
        )
        XCTAssertNotEqual(englishInUS, englishInGermany)
    }

    // MARK: - Lists

    func testListUsesTheLocalesConjunction() {
        let items = ["Screenshots", "Large files"]
        // A hand-rolled `joined(separator: ", ")` is wrong in every language
        // with a different final conjunction.
        let en = Formatters.list(items, language: .english, region: us)
        let de = Formatters.list(items, language: .german, region: de)
        let ja = Formatters.list(items, language: .japanese, region: jp)
        XCTAssertNotEqual(en, de)
        XCTAssertNotEqual(en, ja)
        XCTAssertTrue(en.contains("and"), "got \(en)")
        XCTAssertTrue(de.contains("und"), "got \(de)")
    }

    func testListHandlesZeroOneAndMany() {
        XCTAssertEqual(Formatters.list([], language: .english), "")
        XCTAssertEqual(Formatters.list(["only"], language: .english), "only")
        // No "and" for a single item, and no separator for none.
        let three = Formatters.list(["a", "b", "c"], language: .english)
        XCTAssertTrue(three.contains("a"))
        XCTAssertTrue(three.contains("c"))
    }

    // MARK: - Locale resolution

    func testOverrideChangesTheLanguageButNotTheRegion() {
        // Picking German on a US device must not silently move the user's dates
        // to the 24-hour clock or their week to Monday — that is the rule, and
        // it matches what iOS gives an app with a per-app language.
        let override = Formatters.locale(for: .german, region: us)
        XCTAssertEqual(override.language.languageCode?.identifier, "de")
        XCTAssertEqual(override.region?.identifier, "US")
        XCTAssertEqual(Formatters.firstWeekday(language: .german, region: us), 1)
    }

    func testNoOverrideReturnsTheDeviceLocaleUntouched() {
        // Rebuilding the device locale from parts would drop script subtags and
        // calendar overrides, so the no-override path must hand it back as-is.
        XCTAssertEqual(Formatters.locale(for: nil, region: nil), Locale.current)
    }

    func testEveryShippedLanguageProducesAUsableLocale() {
        for language in AppLanguage.concreteLanguages {
            let locale = Formatters.locale(for: language)
            XCTAssertFalse(locale.identifier.isEmpty, "\(language.rawValue) produced an empty locale")
            // A size must format without trapping in every language.
            XCTAssertFalse(Formatters.fileSize(1_500_000, language: language).isEmpty)
            XCTAssertEqual(Formatters.orderedWeekdays(language: language).count, 7)
        }
    }

    // MARK: - Plurals

    /// True when the text contains a Cyrillic letter (U+0400–U+04FF).
    ///
    /// `Character` has no `isCyrillic`, so this checks the scalars directly.
    private func containsCyrillic(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
    }

    /// The half of plural handling that does work: the *variants* are the chosen
    /// language's, because they come from that language's `.stringsdict`.
    ///
    /// This runs under whatever `Locale.current` the test host has, so it must
    /// not assert a category-dependent form — see the next test for why.
    func testPluralVariantsComeFromTheChosenLanguage() {
        // 5 is `many` in Russian and `other` in English. English rules select
        // `other` for 5, so under an English test host this renders the Russian
        // `other` form. Asserting the *script* proves the variant is Russian
        // without depending on which category got selected.
        let russian = L10n.format("%lld items", language: .russian, 5)
        XCTAssertTrue(
            containsCyrillic(russian),
            "Expected a Russian form, got: \(russian)"
        )
        XCTAssertTrue(russian.contains("5"), "Expected the count, got: \(russian)")
    }

    /// Documents a known limitation rather than asserting correct behaviour.
    ///
    /// `String.localizedStringWithFormat` picks the CLDR plural category with
    /// `Locale.current`, and no Foundation API accepts a locale for that. When
    /// the app language and the device language differ, the wrong category can
    /// be selected even though the variants themselves are right.
    ///
    /// The test asserts the *current* behaviour so the day someone lands real
    /// category selection, this fails and points at the fix. It is deliberately
    /// not written as "assert correct" — that would fail today and be muted.
    func testPluralCategoryFollowsTheDeviceLocaleNotTheAppLanguage() throws {
        // Only meaningful when the host is not already Russian.
        try XCTSkipIf(
            Locale.current.language.languageCode == "ru",
            "Host is Russian, so the wrong category would not be observable."
        )

        let counts = [1, 2, 5, 21]
        let rendered = counts.map { L10n.format("%lld items", language: .russian, $0) }

        // The variants are Russian in every case — the language half works.
        for (count, text) in zip(counts, rendered) {
            XCTAssertTrue(
                containsCyrillic(text),
                "\(count) did not render a Russian form: \(text)"
            )
        }

        // And the known gap: under a non-Russian device locale, Russian's `many`
        // form is never selected, so 5 does not read "5 объектов". (English
        // rules pick `other` for 5; Russian `many` is `%lld объектов`.)
        let five = L10n.format("%lld items", language: .russian, 5)
        XCTAssertNotEqual(
            five, "5 объектов",
            """
            Russian plural categories now resolve correctly under a foreign \
            device locale. Remove the limitation note on L10n.format and \
            tighten this test into a real assertion.
            """
        )
    }

    // MARK: - Code-built cleanup strings

    /// The sentences the cleanup tools assemble in code rather than as `Text`
    /// literals, pinned to German.
    ///
    /// The three batch summaries were raw interpolation
    /// (`"Compressed \(done) of \(total)."`), and an interpolated literal is not
    /// a catalog key, so every one of them shipped the English sentence in all
    /// 20 languages while the coverage gate reported 100%. The scan-progress
    /// details are here for the same reason: the tool scaffold renders them
    /// verbatim, so the sentence has to be finished before it gets there.
    ///
    /// Asserting the German word, not just "differs from English", is what makes
    /// this a regression test: a key that loses its translations falls back to
    /// the English text and fails here.
    func testCodeBuiltCleanupStringsResolveToTheChosenLanguage() {
        let issues = L10n.format(
            "%lld issues found",
            language: .german,
            fallback: "%lld issues found",
            3
        )
        XCTAssertTrue(issues.contains("Probleme"), "expected the German noun, got: \(issues)")
        XCTAssertFalse(issues.contains("issues"), "still English: \(issues)")

        // The Smart Categories scan detail, which the tool scaffold renders
        // verbatim, so the sentence has to be finished before it gets there.
        let photos = L10n.format("%lld photos", language: .german, fallback: "%lld photo", 5)
        XCTAssertEqual(photos, "5 Fotos", "scan detail stayed English: \(photos)")

        let compressed = L10n.format(
            "Compressed %lld of %lld. %lld failed.",
            language: .german,
            8, 10, 2
        )
        XCTAssertTrue(compressed.contains("komprimiert"), "got: \(compressed)")
        // The three counts must land in the order the English sentence reads:
        // all three are `%lld`, so a reordered translation would still pass the
        // placeholder-parity gate and print the wrong numbers.
        XCTAssertEqual(
            compressed.split(whereSeparator: { !$0.isNumber }).map(String.init).filter { !$0.isEmpty },
            ["8", "10", "2"],
            "counts out of order: \(compressed)"
        )

        let converted = L10n.format(
            "Converted %lld of %lld. %lld failed.",
            language: .german,
            8, 10, 2
        )
        XCTAssertTrue(converted.contains("konvertiert"), "got: \(converted)")
        XCTAssertEqual(
            converted.split(whereSeparator: { !$0.isNumber }).map(String.init).filter { !$0.isEmpty },
            ["8", "10", "2"],
            "counts out of order: \(converted)"
        )
    }
}
