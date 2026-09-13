import AppIntents

/// Exposes TidyByte's intents to Siri and Spotlight as App Shortcuts. Each
/// phrase must contain `\(.applicationName)`.
struct TidybyteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartCleanupIntent(),
            phrases: [
                "Start a cleanup session with \(.applicationName)",
                "Clean up photos with \(.applicationName)",
                "Tidy my photos with \(.applicationName)"
            ],
            shortTitle: "Start Cleanup",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: ShowStorageIntent(),
            phrases: [
                "Show storage in \(.applicationName)",
                "Check my storage with \(.applicationName)"
            ],
            shortTitle: "Show Storage",
            systemImageName: "chart.pie"
        )
        AppShortcut(
            intent: CleanScreenshotsIntent(),
            phrases: [
                "Clean screenshots with \(.applicationName)"
            ],
            shortTitle: "Clean Screenshots",
            systemImageName: "camera.viewfinder"
        )
        AppShortcut(
            intent: FreeSpaceIntent(),
            phrases: [
                "How much can I free with \(.applicationName)",
                "Check free space with \(.applicationName)"
            ],
            shortTitle: "How Much Can I Free?",
            systemImageName: "arrow.down.circle"
        )
        AppShortcut(
            intent: ShowSavingsIntent(),
            phrases: [
                "Show my savings in \(.applicationName)"
            ],
            shortTitle: "Show My Savings",
            systemImageName: "chart.line.uptrend.xyaxis"
        )
    }
}
