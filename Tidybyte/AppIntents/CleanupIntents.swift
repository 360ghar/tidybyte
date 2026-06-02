import AppIntents

/// Opens the app and starts a swipe cleanup session.
struct StartCleanupIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Cleanup Session"
    static var description = IntentDescription("Open TidyByte and start reviewing photos.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.shared.link = .swipe
        return .result()
    }
}

/// Opens the app on the Storage dashboard.
struct ShowStorageIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Storage"
    static var description = IntentDescription("Open TidyByte's storage dashboard.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.shared.link = .storage
        return .result()
    }
}

/// Opens the app directly in the Screenshots cleanup tool.
struct CleanScreenshotsIntent: AppIntent {
    static var title: LocalizedStringResource = "Clean Screenshots"
    static var description = IntentDescription("Open TidyByte's screenshot cleaner.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.shared.link = .cleanupTool(.screenshots)
        return .result()
    }
}
