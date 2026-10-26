import Foundation
import Observation

@MainActor
@Observable
final class AppNavigation {
    var selectedTab: AppTab = .swipe
    var cleanupPath: [CleanupTool] = []
    /// Push stack for the Storage tab. Storage previously had no stack; the
    /// Activity & Savings screen is its first push destination.
    var storagePath: [StorageRoute] = []
    private(set) var swipeDismissRequestID = UUID()

    /// One‑shot channel for external tabs (e.g., Storage) to launch a Swipe session
    /// with a custom filter. SwipeHomeView consumes this via `consumePendingSwipeFilter()`.
    private(set) var pendingSwipeFilter: SwipeFilter?

    /// A navigation request parked because a mounted session still holds
    /// uncommitted deletions. See `parkIfSessionHasPendingDeletions`.
    private(set) var deferredLink: DeepLink?

    /// The live swipe session, weakly held through its completion screen.
    /// Lets deep-link launches respect the session's
    /// pending-deletion review gate instead of tearing it down blindly.
    private(set) weak var activeSwipeSession: SwipeSessionViewModel?
    private var activeSwipeSessionTab: AppTab?

    var isShowingSwipeCompletion: Bool {
        selectedTab == activeSwipeSessionTab && activeSwipeSession?.showCompletion == true
    }

    func setActiveSwipeSession(_ session: SwipeSessionViewModel?) {
        activeSwipeSession = session
        activeSwipeSessionTab = session == nil ? nil : selectedTab
    }

    func showCleanup(tool: CleanupTool? = nil) {
        let link: DeepLink = tool.map(DeepLink.cleanupTool) ?? .cleanupHome
        guard !parkIfSessionHasPendingDeletions(link) else { return }
        if let tool {
            cleanupPath = [tool]
        } else {
            cleanupPath.removeAll()
        }
        selectedTab = .cleanup
        requestSwipeDismissal()
    }

    func showCleanupHome() {
        guard !parkIfSessionHasPendingDeletions(.cleanupHome) else { return }
        cleanupPath.removeAll()
        selectedTab = .cleanup
        requestSwipeDismissal()
    }

    func returnToSwipeHome() {
        guard !parkIfSessionHasPendingDeletions(.swipe) else { return }
        cleanupPath.removeAll()
        selectedTab = .swipe
        requestSwipeDismissal()
    }

    /// Applies an external navigation request from a widget tap or App Intent.
    func handle(_ link: DeepLink) {
        switch link {
        case .storage:
            guard !parkIfSessionHasPendingDeletions(link) else { return }
            cleanupPath.removeAll()
            storagePath.removeAll()
            selectedTab = .storage
            requestSwipeDismissal()
        case .activity:
            showActivity()
        case .swipe:
            returnToSwipeHome()
        case .cleanupHome:
            showCleanupHome()
        case .cleanupTool(let tool):
            showCleanup(tool: tool)
        }
    }

    /// Switches tabs because the user tapped one, retiring any parked request
    /// first. A tab tap is an explicit destination; replaying an older parked
    /// one afterwards would override the choice they just made.
    ///
    /// Programmatic switches (deep links, App Intents) go through `handle` or
    /// the `show…` methods instead, where parking is the whole point.
    func selectTabManually(_ tab: AppTab) {
        deferredLink = nil
        selectedTab = tab
    }

    /// Pushes the Activity & Savings screen inside the Storage tab.
    ///
    /// Not gated: this replaces the Storage stack, which never hosts a swipe
    /// session, so any session in the Cleanup stack survives untouched.
    func showActivity() {
        storagePath = [.activity]
        selectedTab = .storage
        requestSwipeDismissal()
    }

    /// Parks a request that would destroy a hosted session's uncommitted
    /// deletions, and routes the user to that review instead. Returns whether it
    /// parked, so every caller reads `guard !park… else { return }`.
    ///
    /// The marked ids live only in the session view model, and the cleanup stack
    /// is what owns that model. Collapsing the stack (`cleanupPath.removeAll()`,
    /// or replacing it with `[tool]`) therefore destroys the deletions the user
    /// was about to confirm — with no prompt and nothing to restore them.
    ///
    /// When nothing is pending the navigation really happens, so any request
    /// parked earlier is superseded: the newest destination wins, and replaying
    /// the old one afterwards would override the choice the user just made.
    private func parkIfSessionHasPendingDeletions(_ link: DeepLink) -> Bool {
        if let session = activeSwipeSession, session.hasPendingDeletions {
            deferredLink = link
            session.requestDeletionReview()
            return true
        }
        deferredLink = nil
        return false
    }

    /// Replays a parked request once no session holds uncommitted deletions.
    /// Safe to call at any time; a no-op otherwise.
    ///
    /// Two deliberate waits:
    /// - Re-checks `hasPendingDeletions` instead of trusting the caller's timing:
    ///   the session view can disappear without being destroyed (a tab switch, a
    ///   sheet), and replaying then would be the very teardown this prevents.
    /// - Holds while the completion review is on screen. Its exit buttons are an
    ///   explicit "take me here" that outranks a request parked before it, and
    ///   teleporting the user off the results they just produced is the same
    ///   surprise this fix exists to remove.
    func applyDeferredLinkIfPossible() {
        guard let link = deferredLink else { return }
        if let session = activeSwipeSession, session.hasPendingDeletions { return }
        guard !isShowingSwipeCompletion else { return }
        deferredLink = nil
        handle(link)
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
        // A mounted session with uncommitted deletions must not be torn down
        // blindly — surface its completion review instead; the queued filter
        // replays when the user next lands on the swipe home (A1).
        if let session = activeSwipeSession, session.hasPendingDeletions {
            pendingSwipeFilter = filter
            selectedTab = .swipe
            session.requestDeletionReview()
            return
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

/// Push destinations inside the Storage tab (the tab's `NavigationStack`).
enum StorageRoute: Hashable {
    case activity
}
