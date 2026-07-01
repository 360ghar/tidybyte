import AppIntents

/// Opens the app and starts a swipe cleanup session.
struct StartCleanupIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a Cleanup Session"
    static let description = IntentDescription("Open TidyByte and start reviewing photos.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.shared.link = .swipe
        return .result()
    }
}

/// Opens the app on the Storage dashboard.
struct ShowStorageIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Storage"
    static let description = IntentDescription("Open TidyByte's storage dashboard.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.shared.link = .storage
        return .result()
    }
}

/// Opens the app directly in the Screenshots cleanup tool.
struct CleanScreenshotsIntent: AppIntent {
    static let title: LocalizedStringResource = "Clean Screenshots"
    static let description = IntentDescription("Open TidyByte's screenshot cleaner.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.shared.link = .cleanupTool(.screenshots)
        return .result()
    }
}
