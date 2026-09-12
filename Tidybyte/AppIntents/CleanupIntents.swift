import AppIntents
import Foundation

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

/// Opens the app on the Activity & Savings screen.
struct ShowSavingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Show My Savings"
    static let description = IntentDescription("Open TidyByte's savings summary.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.shared.link = .activity
        return .result()
    }
}

/// Read-only answer to "how much can I free up?" — does NOT open the app.
/// Answers from the cached widget snapshot the app already wrote, so it works
/// from Siri, Spotlight, and Shortcuts without a launch or a library scan.
struct FreeSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "How Much Can I Free Up?"
    static let description = IntentDescription(
        "Tells you how much space TidyByte can help you reclaim."
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = AppGroupStore.loadSnapshot() else {
            return .result(dialog: "Open TidyByte once so it can scan your library.")
        }

        var parts: [String] = []
        if snapshot.screenshotCount > 0 {
            parts.append("\(snapshot.screenshotCount) screenshots")
        }
        if snapshot.largeFileCount > 0 {
            parts.append("\(snapshot.largeFileCount) large files")
        }

        let reclaimable = snapshot.reclaimableBytes.formattedFileSize

        guard !parts.isEmpty else {
            return .result(dialog: "Your library looks tidy. Nothing obvious to clean up.")
        }

        return .result(
            dialog: "You can free about \(reclaimable) — \(parts.joined(separator: " and ")) to review."
        )
    }
}

/// Opens the Duplicates tool. Available in the Shortcuts app (no Siri phrase
/// registered for it, keeping the spoken surface small).
struct FindDuplicatesIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Duplicates"
    static let description = IntentDescription("Open TidyByte's duplicate finder.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.shared.link = .cleanupTool(.duplicates)
        return .result()
    }
}

/// Opens the Video Compression tool.
struct CompressVideosIntent: AppIntent {
    static let title: LocalizedStringResource = "Compress Videos"
    static let description = IntentDescription("Open TidyByte's video compression tool.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.shared.link = .cleanupTool(.videoCompression)
        return .result()
    }
}
