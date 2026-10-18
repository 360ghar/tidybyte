import Foundation

/// Locale-aware formatting for everything the user reads as a number, date, or
/// duration.
///
/// These exist because several call sites used formatters that ignore locale
/// entirely. `ByteCountFormatter` has no `locale` property at all, so it always
/// renders "1.5 MB" — German users get a period where their convention is a
/// comma, and Arabic users get Western digits. The replacements below take an
/// explicit locale so the app can follow the device.
///
/// Region always comes from the device, even when the language is overridden in
/// Settings. Someone who switches TidyByte to English while living in Germany
/// still expects "18.10.2026" and Monday as the first day of the week; the
/// language override should not silently move their dates.
enum Formatters {
    /// The locale to format with: the language from the resolved UI language,
    /// the region from the device.
    ///
    /// That split is deliberate. Picking German in TidyByte should change the
    /// *words*, not silently move a US-based user's dates to the 24-hour clock
    /// or their week to Monday. It is also what iOS itself does for a per-app
    /// language: the app receives `de-US` on a US device, not `de-DE`.
    ///
    /// `region` exists so the rule can be tested and reasoned about directly —
    /// asserting German conventions requires a German region, which a
    /// US-configured simulator does not have.
    static func locale(for language: AppLanguage? = nil, region: Locale.Region? = nil) -> Locale {
        let resolved = language ?? LanguagePreferenceStore.stored()

        // No override and no explicit region: hand back the device locale
        // untouched. Rebuilding it from parts would drop script subtags and
        // calendar overrides (a Thai Buddhist calendar, for example).
        if resolved == nil, region == nil { return .current }

        let languageCode = resolved?.code
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"
        guard let resolvedRegion = region ?? Locale.current.region else {
            return Locale(identifier: languageCode)
        }
        return Locale(identifier: "\(languageCode)_\(resolvedRegion.identifier)")
    }

    // MARK: - File Sizes

    /// A decimal file size, in the user's locale.
    ///
    /// Always uses a unit symbol from kB upward, never a spelled-out word.
    /// That is deliberate: Foundation's unit formatter does not pluralize
    /// English (it produces "512 byte"), and routing the byte case through the
    /// String Catalog would mean every one of the 21 languages needs a correct
    /// plural form for a string that essentially never appears — photo-library
    /// assets are never under a kilobyte. A symbol sidesteps grammar entirely
    /// and still reads correctly everywhere: "0.5 kB", "1,5 MB", "١٫٥ م.ب".
    ///
    /// Decimal (1000-based) on purpose: this matches the `.file` byte-count
    /// convention the app used before, so a 10 MB threshold still reads
    /// "10 MB" rather than switching to "9.5 MiB".
    static func fileSize(_ bytes: Int64, language: AppLanguage? = nil, region: Locale.Region? = nil) -> String {
        let locale = locale(for: language, region: region)

        let value = Double(bytes)
        let (scaled, unit): (Double, UnitInformationStorage) = switch bytes {
        case 1_000_000_000_000...: (value / 1e12, .terabytes)
        case 1_000_000_000...: (value / 1e9, .gigabytes)
        case 1_000_000...: (value / 1e6, .megabytes)
        default: (value / 1e3, .kilobytes)
        }

        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        // One fraction digit for ordinary sizes ("1.5 GB"), two below 10 kB so
        // a 20-byte file does not collapse to "0 kB". No grouping separators:
        // "999 MB", never "1,000 MB".
        formatter.numberFormatter.maximumFractionDigits = bytes < 10_000 ? 2 : 1
        formatter.numberFormatter.usesGroupingSeparator = false
        return formatter.string(from: Measurement(value: scaled, unit: unit))
    }

    // MARK: - Dates and Times

    static func mediumDate(_ date: Date, language: AppLanguage? = nil, region: Locale.Region? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale(for: language, region: region)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// A short time in the user's convention: 24-hour for most of the world,
    /// 12-hour with AM/PM for the US and a few others. This is the piece that
    /// makes the reminder footer correct outside the US — the app previously
    /// hardcoded "10 AM".
    static func shortTime(_ date: Date, language: AppLanguage? = nil, region: Locale.Region? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale(for: language, region: region)
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// "3d ago" / "vor 3 Tagen", without the "Updated" prefix.
    static func relativeAge(_ date: Date, language: AppLanguage? = nil, region: Locale.Region? = nil, now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale(for: language, region: region)
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }

    // MARK: - Lists

    /// Joins items with the locale's conjunction: "a, b, and c" in English,
    /// "a, b und c" in German, "a、b、c" in Japanese.
    ///
    /// Worth the call: a hand-rolled `joined(separator: ", ")` is wrong in
    /// every language that uses a different final conjunction, and the app
    /// builds sentences like "12 screenshots and 3 large files" in the
    /// notification body and widget.
    static func list(_ items: [String], language: AppLanguage? = nil, region: Locale.Region? = nil) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        let formatter = ListFormatter()
        formatter.locale = locale(for: language, region: region)
        return formatter.string(from: items) ?? items.joined(separator: ", ")
    }

    static func number(_ value: Int, language: AppLanguage? = nil, region: Locale.Region? = nil) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale(for: language, region: region)
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    // MARK: - Calendar

    /// The device's first day of the week, as a `Calendar` weekday number
    /// (1 = Sunday … 7 = Saturday).
    ///
    /// The reminder picker used to hardcode Sunday, which is wrong for most of
    /// the world: Monday in India, Germany, and Brazil, Saturday in much of the
    /// Middle East. Reading it from the device calendar is the whole fix.
    static func firstWeekday(language: AppLanguage? = nil, region: Locale.Region? = nil) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale(for: language, region: region)
        return calendar.firstWeekday
    }

    /// Weekday names in the device's order, starting from its first day of the
    /// week, paired with the `Calendar` weekday number each name belongs to.
    ///
    /// Returned as pairs rather than a bare array so the reminder picker can
    /// store the stable weekday number while displaying a localized name.
    static func orderedWeekdays(language: AppLanguage? = nil, region: Locale.Region? = nil) -> [(weekday: Int, name: String)] {
        let formatter = DateFormatter()
        formatter.locale = locale(for: language, region: region)
        let names = formatter.weekdaySymbols ?? []
        guard names.count == 7 else { return [] }
        let first = firstWeekday(language: language, region: region)
        return (0..<7).map { offset in
            let index = (first - 1 + offset) % 7
            return (weekday: index + 1, name: names[index])
        }
    }

    /// The localized name of one weekday number, for a stored preference.
    static func weekdayName(_ weekday: Int, language: AppLanguage? = nil, region: Locale.Region? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale(for: language, region: region)
        let names = formatter.weekdaySymbols ?? []
        guard names.indices.contains(weekday - 1) else { return "" }
        return names[weekday - 1]
    }
}
