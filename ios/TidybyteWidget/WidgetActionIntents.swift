import AppIntents
import Foundation

/// Interactive-widget intents. Compiled into the WIDGET target only (this
/// directory is not in the app target's sources), so they can't reference
/// app-only types. Each one queues a `WidgetRoute` in the shared App Group and
/// asks the system to open the app; `RootView` drains the route on activation.
///
/// Kept in the widget bundle rather than the app bundle so the widget's
/// `Button(intent:)` resolves the intent inside its own process without the app
/// needing to be running.

struct StartSwipeWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a Swipe Session"
    static let description = IntentDescription("Open TidyByte and review photos.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        AppGroupStore.savePendingRoute(.swipe)
        return .result()
    }
}

struct CleanScreenshotsWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Clean Screenshots"
    static let description = IntentDescription("Open TidyByte's screenshot cleaner.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        AppGroupStore.savePendingRoute(.screenshots)
        return .result()
    }
}

struct ShowSavingsWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Savings"
    static let description = IntentDescription("Open TidyByte's savings summary.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        AppGroupStore.savePendingRoute(.activity)
        return .result()
    }
}
