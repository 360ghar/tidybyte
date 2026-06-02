import Foundation
import Observation

@MainActor
@Observable
final class AppNavigation {
    var selectedTab: AppTab = .swipe
    var cleanupPath: [CleanupTool] = []
    private(set) var swipeDismissRequestID = UUID()

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
}
