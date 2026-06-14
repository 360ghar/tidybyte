import Foundation
import Observation

@MainActor
@Observable
final class AppNavigation {
    var selectedTab: AppTab = .swipe
    var cleanupPath: [CleanupTool] = []
    private(set) var swipeDismissRequestID = UUID()

    /// One‑shot channel for external tabs (e.g., Storage) to launch a Swipe session
    /// with a custom filter. SwipeHomeView consumes this via `consumePendingSwipeFilter()`.
    private(set) var pendingSwipeFilter: SwipeFilter?

    func showCleanup(tool: CleanupTool? = nil) {
        if let tool {
            cleanupPath = [tool]
        } else {
            cleanupPath.removeAll()
        }
        selectedTab = .cleanup
        requestSwipeDismissal()
    }

    func showCleanupHome() {
        cleanupPath.removeAll()
        selectedTab = .cleanup
        requestSwipeDismissal()
    }

    func returnToSwipeHome() {
        cleanupPath.removeAll()
        selectedTab = .swipe
        requestSwipeDismissal()
    }

    /// Applies an external navigation request from a widget tap or App Intent.
    func handle(_ link: DeepLink) {
        switch link {
        case .storage:
            cleanupPath.removeAll()
            selectedTab = .storage
            requestSwipeDismissal()
        case .swipe:
            returnToSwipeHome()
        case .cleanupHome:
            showCleanupHome()
        case .cleanupTool(let tool):
            showCleanup(tool: tool)
        }
    }

    private func requestSwipeDismissal() {
        swipeDismissRequestID = UUID()
    }

    /// Launch a Swipe session with a custom filter from any tab.
    /// Switches to the Swipe tab and stores the filter for SwipeHomeView to consume.
    /// Note: deliberately does NOT call `requestSwipeDismissal()` — that handler nils
    /// `selectedRoute`, which would race with the pending-filter push and cancel the session.
    func showSwipeSession(filter: SwipeFilter) {
        // Diagnostic only — no behavior change. Large deep-links (e.g. tapping a
        // by-year bucket spanning thousands of assets) are the one heavy payload on
        // this path; logging the size makes a stall diagnosable without capping it
        // (capping would silently truncate what the user asked to review).
        if case .customAssetIds(let ids) = filter, ids.count > 500 {
            AppLog.app.info("Launching Swipe session with \(ids.count, privacy: .public) asset IDs")
        }
        pendingSwipeFilter = filter
        selectedTab = .swipe
    }

    /// Consumes the pending filter (called by SwipeHomeView). Returns nil after first call.
    func consumePendingSwipeFilter() -> SwipeFilter? {
        defer { pendingSwipeFilter = nil }
        return pendingSwipeFilter
    }
}
