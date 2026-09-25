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
        static let hasSeenZoomHint = "hasSeenZoomHint"
        static let defaultCompressionPreset = "defaultCompressionPreset"
        static let defaultPhotoCompressionPreset = "defaultPhotoCompressionPreset"
        static let cleanupRemindersEnabled = "cleanupRemindersEnabled"
        static let reminderWeekday = "reminderWeekday"
        static let recentAlbumIds = "recentAlbumIds"
        static let lastStorageScanAt = "lastStorageScanAt"
        static let successfulActionCount = "successfulActionCount"
        static let lastReviewPromptAt = "lastReviewPromptAt"
        static let pendingReviewMilestone = "pendingReviewMilestone"
        static let chatAlbumIDs = "chatAlbumIDs"
        static let hasRatedApp = "hasRatedApp"
        static let lifetimeFreedBytes = "lifetimeFreedBytes"
        static let lifetimeItemCount = "lifetimeItemCount"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let hasSeenLimitedLibraryNotice = "hasSeenLimitedLibraryNotice"
    }

    static func defaultSwipeFilter(in defaults: UserDefaults = .standard) -> DefaultSwipeFilterPreference {
        DefaultSwipeFilterPreference(rawValue: defaults.string(forKey: Key.defaultSwipeFilter) ?? "") ?? .notSwipedYet
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

    // MARK: - First Run

    /// False until the user finishes the onboarding pages. `RootView` reads this
    /// to decide whether to present onboarding over the tab bar; it is recorded
    /// on finish (and on skip) so the flow is strictly once per install.
    static func hasCompletedOnboarding(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: Key.hasCompletedOnboarding)
    }

    static func saveHasCompletedOnboarding(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: Key.hasCompletedOnboarding)
    }

    /// Whether the first-run onboarding should be presented.
    ///
    /// Pure, so the policy can be pinned by tests. Requiring
    /// `.notDetermined` is what makes this safe for the installed base: the
    /// `hasCompleted` flag is absent (false) for anyone upgrading into the
    /// version that introduced it, but those users have already resolved
    /// permission one way or the other, so they are never re-onboarded. Only a
    /// genuinely fresh install — where nothing has asked yet — qualifies.
    static func shouldPresentOnboarding(
        hasCompleted: Bool,
        permissionState: PhotoPermissionState
    ) -> Bool {
        !hasCompleted && permissionState == .notDetermined
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

    // MARK: - Lifetime Savings Cache

    /// Mirror of the cleanup ledger totals, kept in UserDefaults so the widget
    /// extension and the non-launching `FreeSpaceIntent` can read "freed so
    /// far" without touching SwiftData. NEVER the source of truth — the
    /// `CleanupActivityRecord` / `CompressionRecord` rows are — so
    /// `CleanupLedger.refreshCache` reconciles it from the store during the
    /// daily scan and after every library change.
    static func lifetimeFreed(in defaults: UserDefaults = .standard) -> (bytes: Int64, items: Int) {
        (
            bytes: Int64(defaults.double(forKey: Key.lifetimeFreedBytes)),
            items: defaults.integer(forKey: Key.lifetimeItemCount)
        )
    }

    static func saveLifetimeFreed(bytes: Int64, items: Int, in defaults: UserDefaults = .standard) {
        defaults.set(Double(bytes), forKey: Key.lifetimeFreedBytes)
        defaults.set(items, forKey: Key.lifetimeItemCount)
    }

    /// Increments the cached totals by one cleanup's result. Called from the
    /// ledger's write path (main actor) so the widget reflects a fresh cleanup
    /// before the next full reconcile.
    static func addLifetimeFreed(bytes: Int64, items: Int, in defaults: UserDefaults = .standard) {
        let current = lifetimeFreed(in: defaults)
        saveLifetimeFreed(bytes: current.bytes + bytes, items: current.items + items, in: defaults)
    }

    // MARK: - Happy-Path Review Prompt Gating

    /// Success counts at which the "Enjoying TidyByte?" prompt may appear:
    /// early delight at 3, then rarer; `% 50` keeps long-term users asked
    /// roughly twice a year at their current cleanup cadence.
    private static let reviewMilestones: Set<Int> = [3, 10, 25]

    /// Local cooldown between prompts. The prompt interrupts the user, and
    /// its "Yes" path calls `requestReview`, which Apple caps at 3 per 365
    /// days and suppresses *silently* — so the app must pace itself.
    private static let reviewPromptCooldownDays = 60

    static func successfulActionCount(in defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: Key.successfulActionCount)
    }

    /// True once the user said they like the app (and got the rating ask) or
    /// tapped any App Store rate link. iOS never reports whether a review was
    /// submitted, so this records intent — and a user who showed it is never
    /// asked again.
    static func hasRatedApp(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: Key.hasRatedApp)
    }

    static func saveHasRatedApp(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: Key.hasRatedApp)
    }

    /// Pure decision so tests can pin the policy without UserDefaults.
    /// Returns true when the user has not rated, `successCount` hits a
    /// milestone, AND the cooldown has elapsed (a never-prompted install has
    /// no cooldown).
    static func shouldRequestReview(successCount: Int, lastPromptAt: Date?, hasRated: Bool = false, now: Date = .now) -> Bool {
        guard !hasRated else { return false }
        let isMilestone = reviewMilestones.contains(successCount)
            || (successCount > 0 && successCount % 50 == 0)
        guard isMilestone else { return false }
        guard let lastPromptAt else { return true }
        return now.timeIntervalSince(lastPromptAt) >= TimeInterval(reviewPromptCooldownDays * 24 * 60 * 60)
    }

    /// Records one fully-successful happy-path action. Callers must only invoke
    /// this when nothing failed, nothing was cancelled, and at least one item
    /// was affected — a "success" on a no-op would cheapen the milestone.
    /// Returns true when the caller should present the "Enjoying TidyByte?" prompt.
    @discardableResult
    static func recordSuccessfulAction(now: Date = .now, in defaults: UserDefaults = .standard) -> Bool {
        let count = successfulActionCount(in: defaults) + 1
        defaults.set(count, forKey: Key.successfulActionCount)
        let interval = defaults.double(forKey: Key.lastReviewPromptAt)
        let lastPromptAt: Date? = interval == 0 ? nil : Date(timeIntervalSince1970: interval)
        return shouldRequestReview(
            successCount: count,
            lastPromptAt: lastPromptAt,
            hasRated: hasRatedApp(in: defaults),
            now: now
        )
    }

    /// Call when the prompt is presented. Recorded on presentation, not on the
    /// answer, so "Not really" or a swipe-down still consumes the cooldown
    /// instead of retrying every milestone.
    static func recordReviewPromptDate(_ date: Date = .now, in defaults: UserDefaults = .standard) {
        defaults.set(date.timeIntervalSince1970, forKey: Key.lastReviewPromptAt)
    }

    /// True when a milestone was earned but not presented yet — the user exited
    /// the session mid-deck, so the prompt would have interrupted them.
    /// Persisted because the count has already consumed that milestone: dropping
    /// it would lose the prompt decision for good.
    static func hasPendingReviewMilestone(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: Key.pendingReviewMilestone)
    }

    /// Claims (false) or records (true) the held milestone.
    static func savePendingReviewMilestone(_ pending: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(pending, forKey: Key.pendingReviewMilestone)
    }
}
