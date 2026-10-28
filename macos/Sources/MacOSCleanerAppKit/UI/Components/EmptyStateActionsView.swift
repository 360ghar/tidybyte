import SwiftUI
import MacOSCleanerCore

/// Shared recovery-button cluster for empty states (proposed actions, undo
/// history, relationship graph). Previously copy-pasted in three views and
/// drifting; every empty state now offers identical recovery affordances.
struct EmptyStateActionsView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        HStack(spacing: 10) {
            SecondaryButton(
                title: String(localized: "New Scan…"),
                icon: "magnifyingglass",
                action: {
                    model.showsScanSetup = true
                }
            )
            SecondaryButton(
                title: String(localized: "Re-run with safer mode"),
                icon: "shield.lefthalf.fill",
                action: {
                    model.runSaferScan()
                }
            )
            if model.generatedReportURL != nil {
                SecondaryButton(
                    title: String(localized: "View last report"),
                    icon: "doc.plaintext",
                    action: {
                        model.openLatestReport()
                    }
                )
            }
        }
    }
}
