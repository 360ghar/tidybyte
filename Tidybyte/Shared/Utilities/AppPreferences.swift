import Foundation

enum DefaultSwipeFilterPreference: String, CaseIterable, Sendable {
    case notSwipedYet
    case allMedia
    case notInAnyAlbum

    var title: String {
        switch self {
        case .notSwipedYet: "Not Swiped Yet"
        case .allMedia: "All Media"
        case .notInAnyAlbum: "Not in Any User Album"
        }
    }

    var swipeFilter: SwipeFilter {
        switch self {
        case .notSwipedYet: .notSwipedYet
        case .allMedia: .allMedia
        case .notInAnyAlbum: .notInAnyAlbum
        }
    }
}

enum AppPreferences {
    enum Key {
        static let defaultSwipeFilter = "defaultSwipeFilter"
        static let similarPhotoTimeWindow = "similarPhotoTimeWindow"
        static let blurSensitivity = "blurSensitivity"
        static let smartCategorySensitivity = "smartCategorySensitivity"
        static let largeFileThresholdMB = "largeFileThresholdMB"
        static let defaultCompressionPreset = "defaultCompressionPreset"
        static let defaultPhotoCompressionPreset = "defaultPhotoCompressionPreset"
        static let cleanupRemindersEnabled = "cleanupRemindersEnabled"
        static let reminderWeekday = "reminderWeekday"
        static let recentAlbumIds = "recentAlbumIds"
        static let lastStorageScanAt = "lastStorageScanAt"
    }

    static func defaultSwipeFilter(in defaults: UserDefaults = .standard) -> DefaultSwipeFilterPreference {
        DefaultSwipeFilterPreference(rawValue: defaults.string(forKey: Key.defaultSwipeFilter) ?? "") ?? .notSwipedYet
    }

    static func saveDefaultSwipeFilter(_ filter: DefaultSwipeFilterPreference, in defaults: UserDefaults = .standard) {
        defaults.set(filter.rawValue, forKey: Key.defaultSwipeFilter)
    }

    static func similarPhotoTimeWindow(in defaults: UserDefaults = .standard) -> Double {
        defaults.double(forKey: Key.similarPhotoTimeWindow).nonZeroOr(5.0)
    }

    static func saveSimilarPhotoTimeWindow(_ value: Double, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: Key.similarPhotoTimeWindow)
    }

    static func blurSensitivity(in defaults: UserDefaults = .standard) -> BlurSensitivity {
        let rawValue = defaults.string(forKey: Key.blurSensitivity) ?? BlurSensitivity.medium.rawValue
        return BlurSensitivity(rawValue: rawValue) ?? .medium
    }

    static func saveBlurSensitivity(_ sensitivity: BlurSensitivity, in defaults: UserDefaults = .standard) {
        defaults.set(sensitivity.rawValue, forKey: Key.blurSensitivity)
    }

    static func smartCategorySensitivity(in defaults: UserDefaults = .standard) -> CategorySensitivity {
        let rawValue = defaults.string(forKey: Key.smartCategorySensitivity) ?? CategorySensitivity.balanced.rawValue
        return CategorySensitivity(rawValue: rawValue) ?? .balanced
    }

    static func saveSmartCategorySensitivity(_ sensitivity: CategorySensitivity, in defaults: UserDefaults = .standard) {
        defaults.set(sensitivity.rawValue, forKey: Key.smartCategorySensitivity)
    }

    static func largeFileThresholdMB(in defaults: UserDefaults = .standard) -> Double {
        defaults.double(forKey: Key.largeFileThresholdMB).nonZeroOr(10.0)
    }

    static func saveLargeFileThresholdMB(_ value: Double, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: Key.largeFileThresholdMB)
    }

    /// Convenience: the threshold in bytes (decimal MB), so callers don't each
    /// re-derive `Int64(thresholdMB * 1_000_000)` and risk drifting apart.
    static func largeFileThresholdBytes(in defaults: UserDefaults = .standard) -> Int64 {
        Int64(largeFileThresholdMB(in: defaults) * 1_000_000)
    }

    static func defaultCompressionPresetID(in defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: Key.defaultCompressionPreset) ?? "1080p"
    }

    static func saveDefaultCompressionPresetID(_ presetID: String, in defaults: UserDefaults = .standard) {
        defaults.set(presetID, forKey: Key.defaultCompressionPreset)
    }

    static func defaultPhotoCompressionPresetID(in defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: Key.defaultPhotoCompressionPreset) ?? "high"
    }

    static func saveDefaultPhotoCompressionPresetID(_ presetID: String, in defaults: UserDefaults = .standard) {
        defaults.set(presetID, forKey: Key.defaultPhotoCompressionPreset)
    }

    static func remindersEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: Key.cleanupRemindersEnabled)
    }

    static func saveRemindersEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: Key.cleanupRemindersEnabled)
    }

    /// Weekday (1–7, Sunday=1) for the weekly cleanup reminder. Defaults to 1
    /// (Sunday) to match the Settings picker's default (APP-13): a stored 0
    /// (unset) would otherwise fall outside the 1...7 range and make the daily
    /// refresh skip the reminder copy entirely.
    static func reminderWeekday(in defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: Key.reminderWeekday)
        return stored == 0 ? 1 : stored
    }

    static func saveReminderWeekday(_ weekday: Int, in defaults: UserDefaults = .standard) {
        defaults.set(weekday, forKey: Key.reminderWeekday)
    }

    static func recentAlbumIds(in defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: Key.recentAlbumIds) ?? []
    }

    static func saveRecentAlbumIds(_ albumIds: [String], in defaults: UserDefaults = .standard) {
        defaults.set(albumIds, forKey: Key.recentAlbumIds)
    }

    /// Timestamp of the last heavy storage scan, used to gate the once-per-day
    /// library enumeration independently of whether the SwiftData snapshot saved.
    static func lastStorageScanDate(in defaults: UserDefaults = .standard) -> Date? {
        let interval = defaults.double(forKey: Key.lastStorageScanAt)
        return interval == 0 ? nil : Date(timeIntervalSince1970: interval)
    }

    static func saveLastStorageScanDate(_ date: Date, in defaults: UserDefaults = .standard) {
        defaults.set(date.timeIntervalSince1970, forKey: Key.lastStorageScanAt)
    }
}
